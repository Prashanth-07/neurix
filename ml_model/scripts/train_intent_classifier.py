"""
Intent Classification Model Training Script
============================================
Production-grade training with 5-fold cross-validation for MobileBERT.

Features:
- 5-fold stratified cross-validation
- Early stopping with patience
- Learning rate warmup + linear decay
- Mixed precision training (FP16)
- Label smoothing
- Comprehensive logging and metrics
- Confusion matrix visualization
- Confidence threshold for unclear fallback

Author: AI Assistant
Target: 95-99% accuracy on 6-class intent classification
"""

import os
import sys
import json
import logging
import random
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from torch.optim import AdamW
from torch.amp import GradScaler, autocast

from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import (
    accuracy_score, f1_score, classification_report,
    confusion_matrix, precision_recall_fscore_support
)

import matplotlib.pyplot as plt
import seaborn as sns

from transformers import (
    MobileBertTokenizer,
    MobileBertForSequenceClassification,
    get_linear_schedule_with_warmup
)

# ============================================
# CONFIGURATION
# ============================================

class Config:
    # Paths
    BASE_DIR = Path(__file__).parent.parent
    DATA_DIR = BASE_DIR / "data"
    TRAIN_FILE = DATA_DIR / "train" / "intent_train.csv"
    VAL_FILE = DATA_DIR / "validation" / "intent_val.csv"
    TEST_FILE = DATA_DIR / "test" / "intent_test.csv"

    CHECKPOINT_DIR = BASE_DIR / "checkpoints"
    MODEL_DIR = BASE_DIR / "models"
    RESULTS_DIR = BASE_DIR / "results"
    LOG_DIR = BASE_DIR / "logs"

    # Model
    MODEL_NAME = "google/mobilebert-uncased"
    NUM_LABELS = 6
    MAX_LENGTH = 64

    # Labels
    LABEL2ID = {
        "save": 0,
        "search": 1,
        "reminder": 2,
        "cancel_all": 3,
        "cancel_specific": 4,
        "unclear": 5
    }
    ID2LABEL = {v: k for k, v in LABEL2ID.items()}

    # Training
    BATCH_SIZE = 16
    MAX_EPOCHS = 15
    LEARNING_RATE = 2e-5
    WEIGHT_DECAY = 0.01
    WARMUP_RATIO = 0.1
    DROPOUT = 0.3
    LABEL_SMOOTHING = 0.1

    # Early stopping
    EARLY_STOPPING_PATIENCE = 3

    # Cross-validation
    N_FOLDS = 5

    # Confidence threshold
    CONFIDENCE_THRESHOLD = 0.7

    # Reproducibility
    SEED = 42

    # Device
    DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    USE_AMP = False  # Disable mixed precision for stability


def set_seed(seed):
    """Set all seeds for reproducibility."""
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False


def setup_logging(log_dir):
    """Setup logging configuration."""
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"training_{timestamp}.log"

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )

    return logging.getLogger(__name__)


# ============================================
# DATASET
# ============================================

class IntentDataset(Dataset):
    """Dataset for intent classification."""

    def __init__(self, texts, labels, tokenizer, max_length):
        self.texts = texts
        self.labels = labels
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self):
        return len(self.texts)

    def __getitem__(self, idx):
        text = str(self.texts[idx])
        label = self.labels[idx]

        encoding = self.tokenizer(
            text,
            add_special_tokens=True,
            max_length=self.max_length,
            padding="max_length",
            truncation=True,
            return_attention_mask=True,
            return_tensors="pt"
        )

        return {
            "input_ids": encoding["input_ids"].flatten(),
            "attention_mask": encoding["attention_mask"].flatten(),
            "label": torch.tensor(label, dtype=torch.long)
        }


def load_data(config):
    """Load and combine all data for cross-validation."""

    # Load all CSV files
    train_df = pd.read_csv(config.TRAIN_FILE)
    val_df = pd.read_csv(config.VAL_FILE)
    test_df = pd.read_csv(config.TEST_FILE)

    # Combine train and validation for CV (keep test separate)
    cv_df = pd.concat([train_df, val_df], ignore_index=True)

    # Convert labels to IDs
    cv_df["label_id"] = cv_df["label"].map(config.LABEL2ID)
    test_df["label_id"] = test_df["label"].map(config.LABEL2ID)

    return cv_df, test_df


# ============================================
# MODEL
# ============================================

class IntentClassifier(nn.Module):
    """MobileBERT-based intent classifier with custom head."""

    def __init__(self, config):
        super().__init__()

        # Use default dropout from pretrained model to preserve weights
        self.bert = MobileBertForSequenceClassification.from_pretrained(
            config.MODEL_NAME,
            num_labels=config.NUM_LABELS
        )

    def forward(self, input_ids, attention_mask, labels=None):
        return self.bert(
            input_ids=input_ids,
            attention_mask=attention_mask,
            labels=labels
        )

    def predict_with_confidence(self, input_ids, attention_mask):
        """Get predictions with confidence scores."""
        with torch.no_grad():
            outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
            probs = torch.softmax(outputs.logits, dim=-1)
            confidence, predictions = torch.max(probs, dim=-1)
        return predictions, confidence, probs


# ============================================
# TRAINING
# ============================================

class EarlyStopping:
    """Early stopping to prevent overfitting."""

    def __init__(self, patience=3, min_delta=0.001):
        self.patience = patience
        self.min_delta = min_delta
        self.counter = 0
        self.best_score = None
        self.early_stop = False
        self.best_model_state = None

    def __call__(self, val_accuracy, model):
        score = val_accuracy

        if self.best_score is None:
            self.best_score = score
            self.best_model_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
        elif score < self.best_score + self.min_delta:
            self.counter += 1
            if self.counter >= self.patience:
                self.early_stop = True
        else:
            self.best_score = score
            self.best_model_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            self.counter = 0

        return self.early_stop


def get_loss_criterion(config):
    """Get loss function with label smoothing."""
    return nn.CrossEntropyLoss(label_smoothing=config.LABEL_SMOOTHING)


def train_epoch(model, dataloader, optimizer, scheduler, criterion, scaler, config, logger):
    """Train for one epoch."""
    model.train()
    total_loss = 0
    all_preds = []
    all_labels = []

    for batch_idx, batch in enumerate(dataloader):
        input_ids = batch["input_ids"].to(config.DEVICE)
        attention_mask = batch["attention_mask"].to(config.DEVICE)
        labels = batch["label"].to(config.DEVICE)

        optimizer.zero_grad()

        if config.USE_AMP:
            with autocast(device_type='cuda'):
                outputs = model(input_ids, attention_mask)
                loss = criterion(outputs.logits, labels)

            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            scaler.step(optimizer)
            scaler.update()
        else:
            outputs = model(input_ids, attention_mask)
            loss = criterion(outputs.logits, labels)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()

        scheduler.step()

        total_loss += loss.item()
        preds = torch.argmax(outputs.logits, dim=-1)
        all_preds.extend(preds.cpu().numpy())
        all_labels.extend(labels.cpu().numpy())

        if (batch_idx + 1) % 50 == 0:
            logger.info(f"  Batch {batch_idx + 1}/{len(dataloader)}, Loss: {loss.item():.4f}")

    avg_loss = total_loss / len(dataloader)
    accuracy = accuracy_score(all_labels, all_preds)

    return avg_loss, accuracy


def evaluate(model, dataloader, criterion, config):
    """Evaluate model on validation/test set."""
    model.eval()
    total_loss = 0
    all_preds = []
    all_labels = []
    all_confidences = []

    with torch.no_grad():
        for batch in dataloader:
            input_ids = batch["input_ids"].to(config.DEVICE)
            attention_mask = batch["attention_mask"].to(config.DEVICE)
            labels = batch["label"].to(config.DEVICE)

            outputs = model(input_ids, attention_mask)
            loss = criterion(outputs.logits, labels)

            total_loss += loss.item()

            probs = torch.softmax(outputs.logits, dim=-1)
            confidence, preds = torch.max(probs, dim=-1)

            all_preds.extend(preds.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())
            all_confidences.extend(confidence.cpu().numpy())

    avg_loss = total_loss / len(dataloader)
    accuracy = accuracy_score(all_labels, all_preds)

    # Apply confidence threshold (fallback to unclear)
    adjusted_preds = []
    for pred, conf in zip(all_preds, all_confidences):
        if conf < config.CONFIDENCE_THRESHOLD:
            adjusted_preds.append(config.LABEL2ID["unclear"])
        else:
            adjusted_preds.append(pred)

    adjusted_accuracy = accuracy_score(all_labels, adjusted_preds)

    return avg_loss, accuracy, adjusted_accuracy, all_preds, all_labels, all_confidences


def train_fold(fold, train_loader, val_loader, config, logger):
    """Train a single fold."""
    logger.info(f"\n{'='*60}")
    logger.info(f"FOLD {fold + 1}/{config.N_FOLDS}")
    logger.info(f"{'='*60}")

    # Initialize model
    model = IntentClassifier(config).to(config.DEVICE)

    # Optimizer
    optimizer = AdamW(
        model.parameters(),
        lr=config.LEARNING_RATE,
        weight_decay=config.WEIGHT_DECAY
    )

    # Scheduler with warmup
    total_steps = len(train_loader) * config.MAX_EPOCHS
    warmup_steps = int(total_steps * config.WARMUP_RATIO)

    scheduler = get_linear_schedule_with_warmup(
        optimizer,
        num_warmup_steps=warmup_steps,
        num_training_steps=total_steps
    )

    # Loss function with label smoothing
    criterion = get_loss_criterion(config)

    # Mixed precision scaler
    scaler = GradScaler('cuda') if config.USE_AMP else None

    # Early stopping
    early_stopping = EarlyStopping(patience=config.EARLY_STOPPING_PATIENCE)

    # Training history
    history = {
        "train_loss": [],
        "train_acc": [],
        "val_loss": [],
        "val_acc": [],
        "val_acc_adjusted": []
    }

    best_val_acc = 0

    for epoch in range(config.MAX_EPOCHS):
        logger.info(f"\nEpoch {epoch + 1}/{config.MAX_EPOCHS}")
        logger.info("-" * 40)

        # Train
        train_loss, train_acc = train_epoch(
            model, train_loader, optimizer, scheduler, criterion, scaler, config, logger
        )

        # Validate
        val_loss, val_acc, val_acc_adj, _, _, _ = evaluate(
            model, val_loader, criterion, config
        )

        # Log metrics
        logger.info(f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.4f}")
        logger.info(f"Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.4f}, Val Acc (adjusted): {val_acc_adj:.4f}")

        # Update history
        history["train_loss"].append(train_loss)
        history["train_acc"].append(train_acc)
        history["val_loss"].append(val_loss)
        history["val_acc"].append(val_acc)
        history["val_acc_adjusted"].append(val_acc_adj)

        # Track best
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            logger.info(f"  New best validation accuracy: {best_val_acc:.4f}")

        # Early stopping check
        if early_stopping(val_acc, model):
            logger.info(f"Early stopping triggered at epoch {epoch + 1}")
            break

    # Restore best model
    model.load_state_dict(early_stopping.best_model_state)

    return model, history, early_stopping.best_score


def run_cross_validation(cv_df, tokenizer, config, logger):
    """Run 5-fold cross-validation."""
    logger.info("\n" + "="*60)
    logger.info("STARTING 5-FOLD CROSS-VALIDATION")
    logger.info("="*60)

    # Prepare data
    texts = cv_df["text"].values
    labels = cv_df["label_id"].values

    # Stratified K-Fold
    skf = StratifiedKFold(n_splits=config.N_FOLDS, shuffle=True, random_state=config.SEED)

    fold_results = []
    all_histories = []
    best_fold = -1
    best_fold_acc = 0
    best_model_state = None

    for fold, (train_idx, val_idx) in enumerate(skf.split(texts, labels)):
        # Split data
        train_texts = texts[train_idx]
        train_labels = labels[train_idx]
        val_texts = texts[val_idx]
        val_labels = labels[val_idx]

        # Create datasets
        train_dataset = IntentDataset(train_texts, train_labels, tokenizer, config.MAX_LENGTH)
        val_dataset = IntentDataset(val_texts, val_labels, tokenizer, config.MAX_LENGTH)

        # Create dataloaders
        train_loader = DataLoader(
            train_dataset,
            batch_size=config.BATCH_SIZE,
            shuffle=True,
            num_workers=0,
            pin_memory=True
        )
        val_loader = DataLoader(
            val_dataset,
            batch_size=config.BATCH_SIZE,
            shuffle=False,
            num_workers=0,
            pin_memory=True
        )

        # Train fold
        model, history, best_acc = train_fold(fold, train_loader, val_loader, config, logger)

        # Save fold checkpoint
        checkpoint_path = config.CHECKPOINT_DIR / f"fold_{fold + 1}_best.pt"
        torch.save(model.state_dict(), checkpoint_path)
        logger.info(f"Saved fold {fold + 1} checkpoint to {checkpoint_path}")

        # Store results
        fold_results.append({
            "fold": fold + 1,
            "best_val_accuracy": best_acc,
            "epochs_trained": len(history["train_loss"])
        })
        all_histories.append(history)

        # Track best fold
        if best_acc > best_fold_acc:
            best_fold_acc = best_acc
            best_fold = fold
            best_model_state = {k: v.clone() for k, v in model.state_dict().items()}

    # Summary
    logger.info("\n" + "="*60)
    logger.info("CROSS-VALIDATION SUMMARY")
    logger.info("="*60)

    accuracies = [r["best_val_accuracy"] for r in fold_results]
    mean_acc = np.mean(accuracies)
    std_acc = np.std(accuracies)

    for result in fold_results:
        logger.info(f"Fold {result['fold']}: {result['best_val_accuracy']:.4f} ({result['epochs_trained']} epochs)")

    logger.info(f"\nMean Accuracy: {mean_acc:.4f} (+/- {std_acc:.4f})")
    logger.info(f"Best Fold: {best_fold + 1} with accuracy {best_fold_acc:.4f}")

    return fold_results, all_histories, best_fold, best_model_state


def evaluate_on_test(model, test_df, tokenizer, config, logger):
    """Final evaluation on held-out test set."""
    logger.info("\n" + "="*60)
    logger.info("FINAL EVALUATION ON TEST SET")
    logger.info("="*60)

    # Create test dataset
    test_dataset = IntentDataset(
        test_df["text"].values,
        test_df["label_id"].values,
        tokenizer,
        config.MAX_LENGTH
    )

    test_loader = DataLoader(
        test_dataset,
        batch_size=config.BATCH_SIZE,
        shuffle=False,
        num_workers=0
    )

    # Evaluate
    criterion = get_loss_criterion(config)
    _, test_acc, test_acc_adj, preds, labels, confidences = evaluate(
        model, test_loader, criterion, config
    )

    logger.info(f"Test Accuracy: {test_acc:.4f}")
    logger.info(f"Test Accuracy (with confidence threshold): {test_acc_adj:.4f}")

    # Classification report
    report = classification_report(
        labels, preds,
        target_names=list(config.LABEL2ID.keys()),
        digits=4
    )
    logger.info(f"\nClassification Report:\n{report}")

    # Per-class metrics
    precision, recall, f1, support = precision_recall_fscore_support(
        labels, preds, average=None
    )

    class_metrics = {}
    for i, label in config.ID2LABEL.items():
        class_metrics[label] = {
            "precision": float(precision[i]),
            "recall": float(recall[i]),
            "f1": float(f1[i]),
            "support": int(support[i])
        }

    # Confusion matrix
    cm = confusion_matrix(labels, preds)

    return {
        "test_accuracy": test_acc,
        "test_accuracy_adjusted": test_acc_adj,
        "class_metrics": class_metrics,
        "confusion_matrix": cm.tolist(),
        "predictions": preds,
        "labels": labels,
        "confidences": confidences
    }


def plot_results(all_histories, test_results, config, logger):
    """Generate visualization plots."""
    logger.info("\nGenerating plots...")

    config.RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Training curves for all folds
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    for fold, history in enumerate(all_histories):
        epochs = range(1, len(history["train_loss"]) + 1)

        # Train/Val Loss
        axes[0, 0].plot(epochs, history["train_loss"], label=f"Fold {fold+1}", alpha=0.7)
        axes[0, 1].plot(epochs, history["val_loss"], label=f"Fold {fold+1}", alpha=0.7)

        # Train/Val Accuracy
        axes[1, 0].plot(epochs, history["train_acc"], label=f"Fold {fold+1}", alpha=0.7)
        axes[1, 1].plot(epochs, history["val_acc"], label=f"Fold {fold+1}", alpha=0.7)

    axes[0, 0].set_title("Training Loss")
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].set_ylabel("Loss")
    axes[0, 0].legend()
    axes[0, 0].grid(True, alpha=0.3)

    axes[0, 1].set_title("Validation Loss")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].set_ylabel("Loss")
    axes[0, 1].legend()
    axes[0, 1].grid(True, alpha=0.3)

    axes[1, 0].set_title("Training Accuracy")
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].set_ylabel("Accuracy")
    axes[1, 0].legend()
    axes[1, 0].grid(True, alpha=0.3)

    axes[1, 1].set_title("Validation Accuracy")
    axes[1, 1].set_xlabel("Epoch")
    axes[1, 1].set_ylabel("Accuracy")
    axes[1, 1].legend()
    axes[1, 1].grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(config.RESULTS_DIR / "training_curves.png", dpi=150)
    plt.close()
    logger.info(f"Saved training curves to {config.RESULTS_DIR / 'training_curves.png'}")

    # 2. Confusion Matrix
    fig, ax = plt.subplots(figsize=(10, 8))

    cm = np.array(test_results["confusion_matrix"])
    labels = list(config.LABEL2ID.keys())

    sns.heatmap(
        cm, annot=True, fmt="d", cmap="Blues",
        xticklabels=labels, yticklabels=labels,
        ax=ax
    )

    ax.set_title("Confusion Matrix (Test Set)")
    ax.set_xlabel("Predicted")
    ax.set_ylabel("Actual")

    plt.tight_layout()
    plt.savefig(config.RESULTS_DIR / "confusion_matrix.png", dpi=150)
    plt.close()
    logger.info(f"Saved confusion matrix to {config.RESULTS_DIR / 'confusion_matrix.png'}")

    # 3. Confidence distribution
    fig, ax = plt.subplots(figsize=(10, 6))

    confidences = test_results["confidences"]
    predictions = test_results["predictions"]
    labels_actual = test_results["labels"]

    correct = [c for c, p, l in zip(confidences, predictions, labels_actual) if p == l]
    incorrect = [c for c, p, l in zip(confidences, predictions, labels_actual) if p != l]

    ax.hist(correct, bins=20, alpha=0.7, label=f"Correct ({len(correct)})", color="green")
    ax.hist(incorrect, bins=20, alpha=0.7, label=f"Incorrect ({len(incorrect)})", color="red")
    ax.axvline(x=config.CONFIDENCE_THRESHOLD, color="black", linestyle="--", label=f"Threshold ({config.CONFIDENCE_THRESHOLD})")

    ax.set_title("Confidence Distribution")
    ax.set_xlabel("Confidence")
    ax.set_ylabel("Count")
    ax.legend()
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(config.RESULTS_DIR / "confidence_distribution.png", dpi=150)
    plt.close()
    logger.info(f"Saved confidence distribution to {config.RESULTS_DIR / 'confidence_distribution.png'}")


def save_results(fold_results, test_results, config, logger):
    """Save all results to JSON."""
    config.RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    results = {
        "config": {
            "model_name": config.MODEL_NAME,
            "max_length": config.MAX_LENGTH,
            "batch_size": config.BATCH_SIZE,
            "max_epochs": config.MAX_EPOCHS,
            "learning_rate": config.LEARNING_RATE,
            "n_folds": config.N_FOLDS,
            "confidence_threshold": config.CONFIDENCE_THRESHOLD
        },
        "cross_validation": {
            "fold_results": fold_results,
            "mean_accuracy": float(np.mean([r["best_val_accuracy"] for r in fold_results])),
            "std_accuracy": float(np.std([r["best_val_accuracy"] for r in fold_results]))
        },
        "test_results": {
            "accuracy": test_results["test_accuracy"],
            "accuracy_adjusted": test_results["test_accuracy_adjusted"],
            "class_metrics": test_results["class_metrics"],
            "confusion_matrix": test_results["confusion_matrix"]
        },
        "timestamp": datetime.now().isoformat()
    }

    results_path = config.RESULTS_DIR / "cv_results.json"
    with open(results_path, "w") as f:
        json.dump(results, f, indent=2)

    logger.info(f"Saved results to {results_path}")

    return results


# ============================================
# MAIN
# ============================================

def main():
    """Main training function."""
    config = Config()

    # Create directories
    config.CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    config.MODEL_DIR.mkdir(parents=True, exist_ok=True)
    config.RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Setup
    set_seed(config.SEED)
    logger = setup_logging(config.LOG_DIR)

    logger.info("="*60)
    logger.info("INTENT CLASSIFIER TRAINING")
    logger.info("="*60)
    logger.info(f"Device: {config.DEVICE}")
    logger.info(f"Mixed Precision: {config.USE_AMP}")
    logger.info(f"Model: {config.MODEL_NAME}")
    logger.info(f"Batch Size: {config.BATCH_SIZE}")
    logger.info(f"Max Epochs: {config.MAX_EPOCHS}")
    logger.info(f"Learning Rate: {config.LEARNING_RATE}")
    logger.info(f"Cross-Validation Folds: {config.N_FOLDS}")

    # Load tokenizer
    logger.info("\nLoading tokenizer...")
    tokenizer = MobileBertTokenizer.from_pretrained(config.MODEL_NAME)

    # Load data
    logger.info("Loading data...")
    cv_df, test_df = load_data(config)
    logger.info(f"CV samples: {len(cv_df)}, Test samples: {len(test_df)}")

    # Run cross-validation
    fold_results, all_histories, best_fold, best_model_state = run_cross_validation(
        cv_df, tokenizer, config, logger
    )

    # Load best model for final evaluation
    logger.info(f"\nLoading best model (Fold {best_fold + 1})...")
    best_model = IntentClassifier(config).to(config.DEVICE)
    best_model.load_state_dict(best_model_state)

    # Save best model
    best_model_path = config.MODEL_DIR / "best_model.pt"
    torch.save(best_model_state, best_model_path)
    logger.info(f"Saved best model to {best_model_path}")

    # Evaluate on test set
    test_results = evaluate_on_test(best_model, test_df, tokenizer, config, logger)

    # Generate plots
    plot_results(all_histories, test_results, config, logger)

    # Save all results
    results = save_results(fold_results, test_results, config, logger)

    # Final summary
    logger.info("\n" + "="*60)
    logger.info("TRAINING COMPLETE")
    logger.info("="*60)
    logger.info(f"CV Mean Accuracy: {results['cross_validation']['mean_accuracy']:.4f} (+/- {results['cross_validation']['std_accuracy']:.4f})")
    logger.info(f"Test Accuracy: {results['test_results']['accuracy']:.4f}")
    logger.info(f"Test Accuracy (adjusted): {results['test_results']['accuracy_adjusted']:.4f}")
    logger.info(f"\nBest model saved to: {best_model_path}")
    logger.info(f"Results saved to: {config.RESULTS_DIR}")

    return results


if __name__ == "__main__":
    main()
