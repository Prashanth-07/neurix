"""
Combined Test Evaluation
========================
Evaluates the trained model on all three test sets:
1. intent_test.csv - Synthetic test data from training split
2. adversarial_test.csv - Edge cases, typos, slang
3. user_test.csv - Real-world user samples
"""

import os
import sys
from pathlib import Path

import torch
import pandas as pd
import numpy as np
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
import seaborn as sns
import matplotlib.pyplot as plt

from transformers import MobileBertTokenizer, MobileBertForSequenceClassification


class Config:
    BASE_DIR = Path(__file__).parent.parent
    MODEL_PATH = BASE_DIR / "models" / "best_model.pt"

    # Test files
    INTENT_TEST = BASE_DIR / "data" / "test" / "intent_test.csv"
    ADVERSARIAL_TEST = BASE_DIR / "data" / "test" / "adversarial_test.csv"
    USER_TEST = BASE_DIR / "data" / "test" / "user_test.csv"

    RESULTS_DIR = BASE_DIR / "results"

    MODEL_NAME = "google/mobilebert-uncased"
    MAX_LENGTH = 64
    NUM_LABELS = 6
    CONFIDENCE_THRESHOLD = 0.7

    LABEL2ID = {
        "save": 0,
        "search": 1,
        "reminder": 2,
        "cancel_all": 3,
        "cancel_specific": 4,
        "unclear": 5
    }
    ID2LABEL = {v: k for k, v in LABEL2ID.items()}

    DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


class IntentClassifier(torch.nn.Module):
    """MobileBERT-based intent classifier - must match training script."""

    def __init__(self, config):
        super().__init__()
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


def load_model(config):
    """Load the trained model."""
    print(f"Loading model from {config.MODEL_PATH}...")

    model = IntentClassifier(config)
    state_dict = torch.load(config.MODEL_PATH, map_location=config.DEVICE, weights_only=True)
    model.load_state_dict(state_dict)
    model.to(config.DEVICE)
    model.eval()

    return model


def predict(model, tokenizer, texts, config):
    """Make predictions with confidence scores."""
    predictions = []
    confidences = []

    for text in texts:
        encoding = tokenizer(
            text,
            add_special_tokens=True,
            max_length=config.MAX_LENGTH,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )

        input_ids = encoding["input_ids"].to(config.DEVICE)
        attention_mask = encoding["attention_mask"].to(config.DEVICE)

        with torch.no_grad():
            outputs = model(input_ids, attention_mask)
            probs = torch.softmax(outputs.logits, dim=-1)
            confidence, pred = torch.max(probs, dim=-1)

            predictions.append(pred.item())
            confidences.append(confidence.item())

    return predictions, confidences


def evaluate_dataset(model, tokenizer, df, dataset_name, config):
    """Evaluate on a single dataset."""
    print(f"\n{'=' * 60}")
    print(f"EVALUATING: {dataset_name}")
    print(f"{'=' * 60}")
    print(f"Samples: {len(df)}")

    texts = df['text'].tolist()
    labels = [config.LABEL2ID[l] for l in df['label'].tolist()]

    predictions, confidences = predict(model, tokenizer, texts, config)

    # Raw accuracy
    raw_accuracy = accuracy_score(labels, predictions)
    print(f"Raw Accuracy: {raw_accuracy:.4f} ({raw_accuracy*100:.2f}%)")

    # Adjusted accuracy (low confidence -> unclear)
    adjusted_predictions = []
    for pred, conf in zip(predictions, confidences):
        if conf < config.CONFIDENCE_THRESHOLD:
            adjusted_predictions.append(config.LABEL2ID["unclear"])
        else:
            adjusted_predictions.append(pred)

    adjusted_accuracy = accuracy_score(labels, adjusted_predictions)
    print(f"Adjusted Accuracy (threshold={config.CONFIDENCE_THRESHOLD}): {adjusted_accuracy:.4f} ({adjusted_accuracy*100:.2f}%)")

    # Per-class accuracy
    print(f"\nPer-class accuracy:")
    for label_name, label_id in config.LABEL2ID.items():
        mask = [l == label_id for l in labels]
        if sum(mask) > 0:
            label_preds = [p for p, m in zip(predictions, mask) if m]
            label_true = [l for l, m in zip(labels, mask) if m]
            acc = accuracy_score(label_true, label_preds)
            print(f"  {label_name:18} {acc:.4f} ({acc*100:.1f}%) - {sum(mask)} samples")

    # Error analysis
    errors = []
    for text, true_label, pred, conf in zip(texts, labels, predictions, confidences):
        if true_label != pred:
            errors.append({
                'text': text,
                'true': config.ID2LABEL[true_label],
                'predicted': config.ID2LABEL[pred],
                'confidence': conf
            })

    print(f"\nErrors: {len(errors)} / {len(texts)} ({len(errors)/len(texts)*100:.1f}%)")

    return {
        'texts': texts,
        'labels': labels,
        'predictions': predictions,
        'confidences': confidences,
        'raw_accuracy': raw_accuracy,
        'adjusted_accuracy': adjusted_accuracy,
        'errors': errors
    }


def evaluate_combined(config):
    """Run combined evaluation on all test files."""
    print("=" * 60)
    print("COMBINED TEST EVALUATION")
    print("=" * 60)

    # Load model and tokenizer
    model = load_model(config)
    tokenizer = MobileBertTokenizer.from_pretrained(config.MODEL_NAME)

    # Load all datasets
    datasets = {}

    if config.INTENT_TEST.exists():
        datasets['intent_test'] = pd.read_csv(config.INTENT_TEST)
        print(f"Loaded intent_test.csv: {len(datasets['intent_test'])} samples")

    if config.ADVERSARIAL_TEST.exists():
        datasets['adversarial_test'] = pd.read_csv(config.ADVERSARIAL_TEST)
        print(f"Loaded adversarial_test.csv: {len(datasets['adversarial_test'])} samples")

    if config.USER_TEST.exists():
        df = pd.read_csv(config.USER_TEST)
        # Filter out empty rows
        df = df.dropna(subset=['text', 'label'])
        df = df[df['text'].str.strip() != '']
        if len(df) > 0:
            datasets['user_test'] = df
            print(f"Loaded user_test.csv: {len(datasets['user_test'])} samples")

    # Evaluate each dataset
    results = {}
    for name, df in datasets.items():
        results[name] = evaluate_dataset(model, tokenizer, df, name, config)

    # Combine all for final evaluation
    print(f"\n{'=' * 60}")
    print("COMBINED RESULTS (ALL TEST SETS)")
    print("=" * 60)

    all_labels = []
    all_predictions = []
    all_confidences = []
    all_texts = []

    for name, res in results.items():
        all_labels.extend(res['labels'])
        all_predictions.extend(res['predictions'])
        all_confidences.extend(res['confidences'])
        all_texts.extend(res['texts'])

    total_samples = len(all_labels)
    print(f"Total samples: {total_samples}")

    # Combined raw accuracy
    combined_raw_accuracy = accuracy_score(all_labels, all_predictions)
    print(f"\nCombined Raw Accuracy: {combined_raw_accuracy:.4f} ({combined_raw_accuracy*100:.2f}%)")

    # Combined adjusted accuracy
    adjusted_predictions = []
    for pred, conf in zip(all_predictions, all_confidences):
        if conf < config.CONFIDENCE_THRESHOLD:
            adjusted_predictions.append(config.LABEL2ID["unclear"])
        else:
            adjusted_predictions.append(pred)

    combined_adjusted_accuracy = accuracy_score(all_labels, adjusted_predictions)
    print(f"Combined Adjusted Accuracy: {combined_adjusted_accuracy:.4f} ({combined_adjusted_accuracy*100:.2f}%)")

    # Classification report
    print(f"\n{'=' * 60}")
    print("CLASSIFICATION REPORT (Combined)")
    print("=" * 60)
    report = classification_report(
        all_labels, all_predictions,
        target_names=list(config.LABEL2ID.keys()),
        digits=4
    )
    print(report)

    # Confusion matrix
    cm = confusion_matrix(all_labels, all_predictions)
    labels_names = list(config.LABEL2ID.keys())

    # Print text confusion matrix
    print(f"\n{'=' * 60}")
    print("CONFUSION MATRIX")
    print("=" * 60)
    print("\n" + " " * 18 + "Predicted")
    print(" " * 12 + " ".join([f"{l[:6]:>8}" for l in labels_names]))
    print("Actual")
    for i, label in enumerate(labels_names):
        row = " ".join([f"{cm[i][j]:>8}" for j in range(len(labels_names))])
        print(f"  {label:>12} {row}")

    # Save confusion matrix plot
    config.RESULTS_DIR.mkdir(exist_ok=True)

    plt.figure(figsize=(12, 10))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=labels_names, yticklabels=labels_names)
    plt.title(f'Combined Test - Confusion Matrix\n(Raw Accuracy: {combined_raw_accuracy*100:.2f}%, Adjusted: {combined_adjusted_accuracy*100:.2f}%)')
    plt.xlabel('Predicted')
    plt.ylabel('Actual')
    plt.tight_layout()
    plt.savefig(config.RESULTS_DIR / 'confusion_matrix.png', dpi=150)
    plt.close()
    print(f"\nSaved confusion matrix to {config.RESULTS_DIR / 'confusion_matrix.png'}")

    # Per-class accuracy (combined)
    print(f"\n{'=' * 60}")
    print("PER-CLASS ACCURACY (Combined)")
    print("=" * 60)

    for label_name, label_id in config.LABEL2ID.items():
        mask = [l == label_id for l in all_labels]
        if sum(mask) > 0:
            label_preds = [p for p, m in zip(all_predictions, mask) if m]
            label_true = [l for l, m in zip(all_labels, mask) if m]
            acc = accuracy_score(label_true, label_preds)
            print(f"  {label_name:18} {acc:.4f} ({acc*100:.1f}%) - {sum(mask)} samples")

    # Detailed error analysis
    print(f"\n{'=' * 60}")
    print("DETAILED ERROR ANALYSIS")
    print("=" * 60)

    all_errors = []
    for text, true_label, pred, conf in zip(all_texts, all_labels, all_predictions, all_confidences):
        if true_label != pred:
            all_errors.append({
                'text': text,
                'true': config.ID2LABEL[true_label],
                'predicted': config.ID2LABEL[pred],
                'confidence': conf
            })

    print(f"\nTotal errors: {len(all_errors)} / {total_samples} ({len(all_errors)/total_samples*100:.1f}%)")

    # Group errors by confusion type
    error_types = {}
    for e in all_errors:
        key = f"{e['true']} -> {e['predicted']}"
        if key not in error_types:
            error_types[key] = []
        error_types[key].append(e)

    print("\nError breakdown by confusion type:")
    for key, errors in sorted(error_types.items(), key=lambda x: -len(x[1])):
        print(f"\n  {key}: {len(errors)} errors")
        for e in errors[:5]:  # Show first 5 examples
            print(f"    [{e['confidence']:.3f}] \"{e['text'][:60]}...\"" if len(e['text']) > 60 else f"    [{e['confidence']:.3f}] \"{e['text']}\"")

    # Summary by dataset
    print(f"\n{'=' * 60}")
    print("SUMMARY BY DATASET")
    print("=" * 60)
    print(f"{'Dataset':<20} {'Samples':>10} {'Raw Acc':>12} {'Adj Acc':>12}")
    print("-" * 56)
    for name, res in results.items():
        print(f"{name:<20} {len(res['labels']):>10} {res['raw_accuracy']*100:>11.2f}% {res['adjusted_accuracy']*100:>11.2f}%")
    print("-" * 56)
    print(f"{'COMBINED':<20} {total_samples:>10} {combined_raw_accuracy*100:>11.2f}% {combined_adjusted_accuracy*100:>11.2f}%")

    return {
        'combined_raw_accuracy': combined_raw_accuracy,
        'combined_adjusted_accuracy': combined_adjusted_accuracy,
        'total_samples': total_samples,
        'total_errors': len(all_errors),
        'per_dataset': {name: {'raw': res['raw_accuracy'], 'adjusted': res['adjusted_accuracy']}
                       for name, res in results.items()}
    }


if __name__ == "__main__":
    config = Config()
    results = evaluate_combined(config)

    print(f"\n{'=' * 60}")
    print("FINAL SUMMARY")
    print("=" * 60)
    print(f"Combined Raw Accuracy:      {results['combined_raw_accuracy']*100:.2f}%")
    print(f"Combined Adjusted Accuracy: {results['combined_adjusted_accuracy']*100:.2f}%")
    print(f"Total Samples:              {results['total_samples']}")
    print(f"Total Errors:               {results['total_errors']}")
