"""
Convert trained MobileBERT model to ONNX format
for on-device deployment in Flutter using ONNX Runtime
"""

import os
import sys
from pathlib import Path

import torch
import numpy as np
from transformers import (
    MobileBertForSequenceClassification,
    MobileBertTokenizer
)

# ============================================
# CONFIGURATION
# ============================================

BASE_DIR = Path(__file__).parent.parent
CONFIG = {
    'pytorch_model_path': BASE_DIR / 'models' / 'best_model.pt',
    'output_path': BASE_DIR / 'models',
    'max_length': 64,
    'num_labels': 6,
    'model_name': 'google/mobilebert-uncased'
}

# PyTorch model class (must match training script)
class IntentClassifier(torch.nn.Module):
    def __init__(self, num_labels):
        super().__init__()
        self.bert = MobileBertForSequenceClassification.from_pretrained(
            CONFIG['model_name'],
            num_labels=num_labels
        )

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(
            input_ids=input_ids,
            attention_mask=attention_mask
        )
        # Apply softmax to get probabilities
        probs = torch.softmax(outputs.logits, dim=-1)
        return probs


def load_pytorch_model():
    """Load trained PyTorch model"""
    print(f"Loading PyTorch model from {CONFIG['pytorch_model_path']}...")

    model = IntentClassifier(CONFIG['num_labels'])
    state_dict = torch.load(CONFIG['pytorch_model_path'], map_location='cpu', weights_only=True)
    model.load_state_dict(state_dict)
    model.eval()

    return model


def convert_to_onnx(model, tokenizer):
    """Convert PyTorch model to ONNX format"""
    print("Converting to ONNX...")

    # Create dummy inputs
    dummy_text = "remind me to take a walk"
    encoding = tokenizer(
        dummy_text,
        add_special_tokens=True,
        max_length=CONFIG['max_length'],
        padding='max_length',
        truncation=True,
        return_tensors='pt'
    )

    input_ids = encoding['input_ids']
    attention_mask = encoding['attention_mask']

    # Output path
    output_file = CONFIG['output_path'] / 'intent_model.onnx'

    # Export to ONNX
    torch.onnx.export(
        model,
        (input_ids, attention_mask),
        str(output_file),
        export_params=True,
        opset_version=14,  # Use opset 14 for better compatibility
        do_constant_folding=True,
        input_names=['input_ids', 'attention_mask'],
        output_names=['probabilities'],
        dynamic_axes={
            'input_ids': {0: 'batch_size'},
            'attention_mask': {0: 'batch_size'},
            'probabilities': {0: 'batch_size'}
        }
    )

    print(f"Saved ONNX model to: {output_file}")

    # Get file size
    file_size = output_file.stat().st_size / 1024 / 1024
    print(f"Model size: {file_size:.2f} MB")

    return str(output_file)


def optimize_onnx(onnx_path):
    """Optimize ONNX model for mobile deployment"""
    try:
        import onnx
        from onnxruntime.transformers import optimizer
        from onnxruntime.transformers.fusion_options import FusionOptions

        print("Optimizing ONNX model...")

        # Load model
        model = onnx.load(onnx_path)

        # Optimize for MobileBERT
        optimized_model = optimizer.optimize_model(
            onnx_path,
            model_type='bert',
            num_heads=4,  # MobileBERT uses 4 attention heads
            hidden_size=512  # MobileBERT hidden size
        )

        # Save optimized model
        optimized_path = onnx_path.replace('.onnx', '_optimized.onnx')
        optimized_model.save_model_to_file(optimized_path)

        print(f"Saved optimized model to: {optimized_path}")

        # Get file size
        file_size = Path(optimized_path).stat().st_size / 1024 / 1024
        print(f"Optimized model size: {file_size:.2f} MB")

        return optimized_path

    except ImportError:
        print("onnxruntime-tools not installed, skipping optimization")
        return onnx_path
    except Exception as e:
        print(f"Optimization failed: {e}")
        return onnx_path


def test_onnx_model(onnx_path, tokenizer):
    """Test the converted ONNX model"""
    import onnxruntime as ort

    print("\nTesting ONNX model...")

    # Create inference session
    session = ort.InferenceSession(onnx_path, providers=['CPUExecutionProvider'])

    # Get input/output names
    input_names = [i.name for i in session.get_inputs()]
    output_names = [o.name for o in session.get_outputs()]

    print(f"Input names: {input_names}")
    print(f"Output names: {output_names}")

    # Test with sample inputs
    test_texts = [
        "I put my keys in the drawer",
        "Where are my keys?",
        "Remind me to drink water in 5 minutes",
        "Cancel all reminders",
        "Stop my water reminder",
        "Hello"
    ]

    expected_labels = ['save', 'search', 'reminder', 'cancel_all', 'cancel_specific', 'unclear']
    label_names = ['save', 'search', 'reminder', 'cancel_all', 'cancel_specific', 'unclear']

    print("\nTest Results:")
    print("-" * 60)

    correct = 0
    for text, expected in zip(test_texts, expected_labels):
        # Tokenize
        encoding = tokenizer(
            text,
            add_special_tokens=True,
            max_length=CONFIG['max_length'],
            padding='max_length',
            truncation=True,
            return_tensors='np'
        )

        input_ids = encoding['input_ids'].astype(np.int64)
        attention_mask = encoding['attention_mask'].astype(np.int64)

        # Run inference
        outputs = session.run(
            output_names,
            {
                'input_ids': input_ids,
                'attention_mask': attention_mask
            }
        )

        probs = outputs[0][0]
        predicted_idx = np.argmax(probs)
        predicted_label = label_names[predicted_idx]
        confidence = probs[predicted_idx]

        status = "OK" if predicted_label == expected else "FAIL"
        if predicted_label == expected:
            correct += 1

        print(f"{status} | '{text[:40]:<40}' -> {predicted_label:<16} ({confidence:.3f}) [expected: {expected}]")

    print("-" * 60)
    print(f"Accuracy: {correct}/{len(test_texts)} ({100*correct/len(test_texts):.1f}%)")


def save_vocab(tokenizer):
    """Save vocabulary for tokenization in Flutter"""
    vocab_file = CONFIG['output_path'] / 'vocab.txt'

    # Get vocabulary
    vocab = tokenizer.get_vocab()
    sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])

    with open(vocab_file, 'w', encoding='utf-8') as f:
        for token, idx in sorted_vocab:
            f.write(f"{token}\n")

    print(f"Saved vocabulary to: {vocab_file}")
    print(f"Vocabulary size: {len(vocab)}")


# ============================================
# MAIN
# ============================================

def main():
    print("=" * 50)
    print("ONNX Model Conversion")
    print("=" * 50)

    # Load tokenizer
    print("\nLoading tokenizer...")
    tokenizer = MobileBertTokenizer.from_pretrained(CONFIG['model_name'])

    # Load PyTorch model
    print("\nLoading PyTorch model...")
    model = load_pytorch_model()

    # Convert to ONNX
    print("\nConverting to ONNX...")
    onnx_path = convert_to_onnx(model, tokenizer)

    # Try to optimize (optional)
    print("\nOptimizing ONNX model...")
    optimized_path = optimize_onnx(onnx_path)

    # Save vocabulary
    print("\nSaving vocabulary...")
    save_vocab(tokenizer)

    # Test the model
    test_onnx_model(onnx_path, tokenizer)

    print("\n" + "=" * 50)
    print("Conversion complete!")
    print("=" * 50)
    print("\nNext steps:")
    print("1. Copy intent_model.onnx to neurix/assets/models/")
    print("2. Copy vocab.txt to neurix/assets/models/")
    print("3. Update IntentClassifierService to use ONNX Runtime")

if __name__ == '__main__':
    main()
