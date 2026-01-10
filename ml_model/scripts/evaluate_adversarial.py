"""
Adversarial Test Evaluation
===========================
Evaluates the trained model on edge cases, typos, slang, and ambiguous inputs.
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

# Configuration
class Config:
    BASE_DIR = Path(__file__).parent.parent
    MODEL_PATH = BASE_DIR / "models" / "best_model.pt"
    ADVERSARIAL_TEST = BASE_DIR / "data" / "test" / "adversarial_test.csv"
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
    all_probs = []

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
            all_probs.append(probs.cpu().numpy()[0])

    return predictions, confidences, all_probs


def evaluate(config):
    """Run adversarial evaluation."""
    print("=" * 60)
    print("ADVERSARIAL TEST EVALUATION")
    print("=" * 60)

    # Load data
    print(f"\nLoading adversarial test data from {config.ADVERSARIAL_TEST}...")
    df = pd.read_csv(config.ADVERSARIAL_TEST)
    print(f"Loaded {len(df)} samples")

    # Show class distribution
    print("\nClass distribution:")
    for label in config.LABEL2ID.keys():
        count = len(df[df['label'] == label])
        print(f"  {label}: {count}")

    # Load model and tokenizer
    model = load_model(config)
    tokenizer = MobileBertTokenizer.from_pretrained(config.MODEL_NAME)

    # Get predictions
    print("\nMaking predictions...")
    texts = df['text'].tolist()
    labels = [config.LABEL2ID[l] for l in df['label'].tolist()]

    predictions, confidences, all_probs = predict(model, tokenizer, texts, config)

    # Calculate raw accuracy
    raw_accuracy = accuracy_score(labels, predictions)
    print(f"\n{'=' * 60}")
    print(f"RAW ACCURACY: {raw_accuracy:.4f} ({raw_accuracy*100:.2f}%)")
    print(f"{'=' * 60}")

    # Apply confidence threshold (fallback to unclear)
    adjusted_predictions = []
    for pred, conf in zip(predictions, confidences):
        if conf < config.CONFIDENCE_THRESHOLD:
            adjusted_predictions.append(config.LABEL2ID["unclear"])
        else:
            adjusted_predictions.append(pred)

    adjusted_accuracy = accuracy_score(labels, adjusted_predictions)
    print(f"ADJUSTED ACCURACY (threshold={config.CONFIDENCE_THRESHOLD}): {adjusted_accuracy:.4f} ({adjusted_accuracy*100:.2f}%)")

    # Classification report
    print(f"\n{'=' * 60}")
    print("CLASSIFICATION REPORT (Raw)")
    print("=" * 60)
    report = classification_report(
        labels, predictions,
        target_names=list(config.LABEL2ID.keys()),
        digits=4
    )
    print(report)

    # Detailed error analysis
    print(f"\n{'=' * 60}")
    print("ERROR ANALYSIS")
    print("=" * 60)

    errors = []
    for i, (text, true_label, pred, conf) in enumerate(zip(texts, labels, predictions, confidences)):
        if true_label != pred:
            errors.append({
                'text': text,
                'true': config.ID2LABEL[true_label],
                'predicted': config.ID2LABEL[pred],
                'confidence': conf
            })

    print(f"\nTotal errors: {len(errors)} / {len(texts)} ({len(errors)/len(texts)*100:.1f}%)")

    if errors:
        print("\nMisclassified samples:")
        print("-" * 80)
        for e in errors[:30]:  # Show first 30 errors
            print(f"Text: '{e['text']}'")
            print(f"  True: {e['true']} | Predicted: {e['predicted']} | Conf: {e['confidence']:.3f}")
            print()

    # Low confidence predictions
    print(f"\n{'=' * 60}")
    print(f"LOW CONFIDENCE PREDICTIONS (< {config.CONFIDENCE_THRESHOLD})")
    print("=" * 60)

    low_conf = [(text, config.ID2LABEL[pred], conf)
                for text, pred, conf in zip(texts, predictions, confidences)
                if conf < config.CONFIDENCE_THRESHOLD]

    print(f"Total: {len(low_conf)} samples")
    for text, pred, conf in low_conf[:20]:
        print(f"  [{conf:.3f}] '{text}' -> {pred}")

    # Confusion matrix
    print(f"\n{'=' * 60}")
    print("CONFUSION MATRIX")
    print("=" * 60)

    cm = confusion_matrix(labels, predictions)
    labels_names = list(config.LABEL2ID.keys())

    # Print text confusion matrix
    print("\n" + " " * 18 + "Predicted")
    print(" " * 12 + " ".join([f"{l[:6]:>8}" for l in labels_names]))
    print("Actual")
    for i, label in enumerate(labels_names):
        row = " ".join([f"{cm[i][j]:>8}" for j in range(len(labels_names))])
        print(f"  {label:>12} {row}")

    # Save confusion matrix plot
    plt.figure(figsize=(10, 8))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=labels_names, yticklabels=labels_names)
    plt.title('Adversarial Test - Confusion Matrix')
    plt.xlabel('Predicted')
    plt.ylabel('Actual')
    plt.tight_layout()
    plt.savefig(config.RESULTS_DIR / 'adversarial_confusion_matrix.png', dpi=150)
    plt.close()
    print(f"\nSaved confusion matrix to {config.RESULTS_DIR / 'adversarial_confusion_matrix.png'}")

    # Summary by category
    print(f"\n{'=' * 60}")
    print("ACCURACY BY CATEGORY")
    print("=" * 60)

    for label_name, label_id in config.LABEL2ID.items():
        mask = [l == label_id for l in labels]
        if sum(mask) > 0:
            label_preds = [p for p, m in zip(predictions, mask) if m]
            label_true = [l for l, m in zip(labels, mask) if m]
            acc = accuracy_score(label_true, label_preds)
            print(f"  {label_name:18} {acc:.4f} ({acc*100:.1f}%) - {sum(mask)} samples")

    return {
        'raw_accuracy': raw_accuracy,
        'adjusted_accuracy': adjusted_accuracy,
        'total_samples': len(texts),
        'total_errors': len(errors),
        'low_confidence_count': len(low_conf)
    }


if __name__ == "__main__":
    config = Config()
    results = evaluate(config)

    print(f"\n{'=' * 60}")
    print("SUMMARY")
    print("=" * 60)
    print(f"Raw Accuracy:      {results['raw_accuracy']*100:.2f}%")
    print(f"Adjusted Accuracy: {results['adjusted_accuracy']*100:.2f}%")
    print(f"Total Errors:      {results['total_errors']}")
    print(f"Low Confidence:    {results['low_confidence_count']}")
