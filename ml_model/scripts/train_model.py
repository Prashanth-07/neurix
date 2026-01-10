"""
Intent Classification Model Training Script
Model: MobileBERT fine-tuned for 6-class classification
Target: 95-99% accuracy
Output: TFLite model for Flutter deployment
"""

import os
import pandas as pd
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix
import torch
from torch.utils.data import Dataset, DataLoader
from transformers import (
    MobileBertTokenizer,
    MobileBertForSequenceClassification,
    AdamW,
    get_linear_schedule_with_warmup
)
from tqdm import tqdm
import warnings
warnings.filterwarnings('ignore')

# ============================================
# CONFIGURATION
# ============================================

CONFIG = {
    # Model
    'model_name': 'google/mobilebert-uncased',
    'num_labels': 6,
    'max_length': 64,

    # Training
    'batch_size': 32,
    'learning_rate': 2e-5,
    'num_epochs': 5,
    'warmup_ratio': 0.1,
    'weight_decay': 0.01,

    # Paths
    'train_path': '../data/train/intent_train.csv',
    'val_path': '../data/validation/intent_val.csv',
    'test_path': '../data/test/intent_test.csv',
    'output_dir': '../models/',

    # Device
    'device': 'cuda' if torch.cuda.is_available() else 'cpu'
}

# Label mapping
LABEL_MAP = {
    'save': 0,
    'search': 1,
    'reminder': 2,
    'cancel_all': 3,
    'cancel_specific': 4,
    'unclear': 5
}

LABEL_NAMES = list(LABEL_MAP.keys())

# ============================================
# DATASET CLASS
# ============================================

class IntentDataset(Dataset):
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
            padding='max_length',
            truncation=True,
            return_tensors='pt'
        )

        return {
            'input_ids': encoding['input_ids'].flatten(),
            'attention_mask': encoding['attention_mask'].flatten(),
            'label': torch.tensor(label, dtype=torch.long)
        }

# ============================================
# DATA LOADING
# ============================================

def load_data(path):
    """Load CSV data and return texts and labels"""
    df = pd.read_csv(path)
    texts = df['text'].tolist()
    labels = [LABEL_MAP[label] for label in df['label'].tolist()]
    return texts, labels

def compute_class_weights(labels):
    """Compute class weights for imbalanced data"""
    class_counts = np.bincount(labels, minlength=CONFIG['num_labels'])
    total = len(labels)
    weights = total / (CONFIG['num_labels'] * class_counts + 1e-6)
    return torch.tensor(weights, dtype=torch.float)

# ============================================
# TRAINING FUNCTIONS
# ============================================

def train_epoch(model, dataloader, optimizer, scheduler, criterion, device):
    model.train()
    total_loss = 0
    correct = 0
    total = 0

    progress_bar = tqdm(dataloader, desc='Training')

    for batch in progress_bar:
        input_ids = batch['input_ids'].to(device)
        attention_mask = batch['attention_mask'].to(device)
        labels = batch['label'].to(device)

        optimizer.zero_grad()

        outputs = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            labels=labels
        )

        loss = outputs.loss
        logits = outputs.logits

        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        scheduler.step()

        total_loss += loss.item()

        _, predicted = torch.max(logits, 1)
        correct += (predicted == labels).sum().item()
        total += labels.size(0)

        progress_bar.set_postfix({
            'loss': f'{loss.item():.4f}',
            'acc': f'{100 * correct / total:.2f}%'
        })

    return total_loss / len(dataloader), correct / total

def evaluate(model, dataloader, device):
    model.eval()
    total_loss = 0
    all_preds = []
    all_labels = []

    with torch.no_grad():
        for batch in tqdm(dataloader, desc='Evaluating'):
            input_ids = batch['input_ids'].to(device)
            attention_mask = batch['attention_mask'].to(device)
            labels = batch['label'].to(device)

            outputs = model(
                input_ids=input_ids,
                attention_mask=attention_mask,
                labels=labels
            )

            total_loss += outputs.loss.item()

            _, predicted = torch.max(outputs.logits, 1)
            all_preds.extend(predicted.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())

    accuracy = np.mean(np.array(all_preds) == np.array(all_labels))

    return total_loss / len(dataloader), accuracy, all_preds, all_labels

# ============================================
# MAIN TRAINING LOOP
# ============================================

def main():
    print("=" * 50)
    print("Intent Classification Model Training")
    print("=" * 50)
    print(f"Device: {CONFIG['device']}")
    print(f"Model: {CONFIG['model_name']}")
    print()

    # Load tokenizer
    print("Loading tokenizer...")
    tokenizer = MobileBertTokenizer.from_pretrained(CONFIG['model_name'])

    # Load data
    print("Loading data...")
    train_texts, train_labels = load_data(CONFIG['train_path'])
    val_texts, val_labels = load_data(CONFIG['val_path'])
    test_texts, test_labels = load_data(CONFIG['test_path'])

    print(f"Train samples: {len(train_texts)}")
    print(f"Validation samples: {len(val_texts)}")
    print(f"Test samples: {len(test_texts)}")
    print()

    # Create datasets
    train_dataset = IntentDataset(train_texts, train_labels, tokenizer, CONFIG['max_length'])
    val_dataset = IntentDataset(val_texts, val_labels, tokenizer, CONFIG['max_length'])
    test_dataset = IntentDataset(test_texts, test_labels, tokenizer, CONFIG['max_length'])

    # Create dataloaders
    train_loader = DataLoader(train_dataset, batch_size=CONFIG['batch_size'], shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=CONFIG['batch_size'])
    test_loader = DataLoader(test_dataset, batch_size=CONFIG['batch_size'])

    # Compute class weights
    class_weights = compute_class_weights(train_labels).to(CONFIG['device'])
    print(f"Class weights: {class_weights}")
    print()

    # Load model
    print("Loading model...")
    model = MobileBertForSequenceClassification.from_pretrained(
        CONFIG['model_name'],
        num_labels=CONFIG['num_labels']
    )
    model.to(CONFIG['device'])

    # Setup optimizer and scheduler
    optimizer = AdamW(
        model.parameters(),
        lr=CONFIG['learning_rate'],
        weight_decay=CONFIG['weight_decay']
    )

    total_steps = len(train_loader) * CONFIG['num_epochs']
    warmup_steps = int(total_steps * CONFIG['warmup_ratio'])

    scheduler = get_linear_schedule_with_warmup(
        optimizer,
        num_warmup_steps=warmup_steps,
        num_training_steps=total_steps
    )

    criterion = torch.nn.CrossEntropyLoss(weight=class_weights)

    # Training loop
    print("Starting training...")
    print()

    best_val_acc = 0

    for epoch in range(CONFIG['num_epochs']):
        print(f"Epoch {epoch + 1}/{CONFIG['num_epochs']}")
        print("-" * 30)

        # Train
        train_loss, train_acc = train_epoch(
            model, train_loader, optimizer, scheduler, criterion, CONFIG['device']
        )

        # Validate
        val_loss, val_acc, _, _ = evaluate(model, val_loader, CONFIG['device'])

        print(f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.4f}")
        print(f"Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.4f}")
        print()

        # Save best model
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), os.path.join(CONFIG['output_dir'], 'best_model.pt'))
            print(f"Saved best model with val_acc: {val_acc:.4f}")

    # Load best model for testing
    print("=" * 50)
    print("Testing best model...")
    model.load_state_dict(torch.load(os.path.join(CONFIG['output_dir'], 'best_model.pt')))

    test_loss, test_acc, test_preds, test_labels = evaluate(model, test_loader, CONFIG['device'])

    print(f"Test Accuracy: {test_acc:.4f}")
    print()

    # Classification report
    print("Classification Report:")
    print(classification_report(test_labels, test_preds, target_names=LABEL_NAMES))

    # Confusion matrix
    print("Confusion Matrix:")
    print(confusion_matrix(test_labels, test_preds))

    # Save model for conversion
    print()
    print("Saving model for TFLite conversion...")
    model.save_pretrained(os.path.join(CONFIG['output_dir'], 'saved_model'))
    tokenizer.save_pretrained(os.path.join(CONFIG['output_dir'], 'saved_model'))

    print()
    print("=" * 50)
    print("Training complete!")
    print(f"Best validation accuracy: {best_val_acc:.4f}")
    print(f"Test accuracy: {test_acc:.4f}")
    print("=" * 50)

if __name__ == '__main__':
    main()
