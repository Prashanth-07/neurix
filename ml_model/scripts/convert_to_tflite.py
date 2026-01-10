"""
Convert trained MobileBERT model to TFLite format
for on-device deployment in Flutter
"""

import os
import sys
from pathlib import Path
import shutil

import torch
import tensorflow as tf
from transformers import (
    TFMobileBertForSequenceClassification,
    MobileBertForSequenceClassification,
    MobileBertTokenizer
)
import numpy as np

# ============================================
# CONFIGURATION
# ============================================

BASE_DIR = Path(__file__).parent.parent
CONFIG = {
    'pytorch_model_path': BASE_DIR / 'models' / 'best_model.pt',
    'temp_hf_path': BASE_DIR / 'models' / 'temp_hf',
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

    def forward(self, input_ids, attention_mask, labels=None):
        return self.bert(
            input_ids=input_ids,
            attention_mask=attention_mask,
            labels=labels
        )

# ============================================
# CONVERSION FUNCTIONS
# ============================================

def load_pytorch_model():
    """Load trained PyTorch model"""
    print(f"Loading PyTorch model from {CONFIG['pytorch_model_path']}...")

    model = IntentClassifier(CONFIG['num_labels'])
    state_dict = torch.load(CONFIG['pytorch_model_path'], map_location='cpu', weights_only=True)
    model.load_state_dict(state_dict)
    model.eval()

    return model


def convert_pytorch_to_tf():
    """Convert PyTorch model to TensorFlow"""
    print("Converting PyTorch model to TensorFlow...")

    # Load PyTorch model
    pt_model = load_pytorch_model()

    # Save in Hugging Face format (for conversion)
    temp_path = CONFIG['temp_hf_path']
    temp_path.mkdir(parents=True, exist_ok=True)

    print(f"Saving PyTorch model to HuggingFace format at {temp_path}...")
    pt_model.bert.save_pretrained(str(temp_path))

    # Save tokenizer too
    tokenizer = MobileBertTokenizer.from_pretrained(CONFIG['model_name'])
    tokenizer.save_pretrained(str(temp_path))

    # Load as TensorFlow model (from_pt=True converts weights)
    print("Loading as TensorFlow model...")
    tf_model = TFMobileBertForSequenceClassification.from_pretrained(
        str(temp_path),
        from_pt=True,
        num_labels=CONFIG['num_labels']
    )

    # Clean up temp directory
    shutil.rmtree(temp_path)
    print("Cleaned up temporary files")

    return tf_model

def create_concrete_function(model, tokenizer):
    """Create a concrete function for TFLite conversion"""

    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, CONFIG['max_length']], dtype=tf.int32, name='input_ids'),
        tf.TensorSpec(shape=[1, CONFIG['max_length']], dtype=tf.int32, name='attention_mask')
    ])
    def serving_fn(input_ids, attention_mask):
        outputs = model(input_ids=input_ids, attention_mask=attention_mask)
        # Apply softmax to get probabilities
        probs = tf.nn.softmax(outputs.logits, axis=-1)
        return probs

    return serving_fn

def convert_to_tflite(model, tokenizer):
    """Convert model to TFLite with SELECT_TF_OPS for full transformer support"""
    print("Creating concrete function...")

    # Get concrete function
    serving_fn = create_concrete_function(model, tokenizer)
    concrete_func = serving_fn.get_concrete_function()

    # Create converter
    print("Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])

    # Apply optimizations
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # Enable SELECT_TF_OPS for ops not in core TFLite (like Pad with specific shapes)
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    converter._experimental_lower_tensor_list_ops = False

    # Convert
    tflite_model = converter.convert()

    # Save
    output_file = CONFIG['output_path'] / 'intent_model.tflite'
    with open(output_file, 'wb') as f:
        f.write(tflite_model)

    print(f"Saved TFLite model to: {output_file}")
    print(f"Model size: {len(tflite_model) / 1024 / 1024:.2f} MB")

    return str(output_file)

def convert_to_tflite_quantized(model, tokenizer):
    """Convert with full INT8 quantization for smaller size"""
    print("Creating concrete function for quantized model...")

    serving_fn = create_concrete_function(model, tokenizer)
    concrete_func = serving_fn.get_concrete_function()

    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])

    # Full integer quantization
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8
    ]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.float32

    # Representative dataset for calibration
    def representative_dataset():
        for _ in range(100):
            # Generate random input for calibration
            input_ids = np.random.randint(0, 30000, size=(1, CONFIG['max_length'])).astype(np.int32)
            attention_mask = np.ones((1, CONFIG['max_length']), dtype=np.int32)
            yield [input_ids, attention_mask]

    converter.representative_dataset = representative_dataset

    try:
        tflite_model = converter.convert()

        output_file = CONFIG['output_path'] / 'intent_model_quantized.tflite'
        with open(output_file, 'wb') as f:
            f.write(tflite_model)

        print(f"Saved quantized TFLite model to: {output_file}")
        print(f"Model size: {len(tflite_model) / 1024 / 1024:.2f} MB")

        return str(output_file)
    except Exception as e:
        print(f"Quantization failed: {e}")
        print("Falling back to default optimization...")
        return None

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

def test_tflite_model(model_path, tokenizer):
    """Test the converted TFLite model"""
    print("\nTesting TFLite model...")

    # Load TFLite model
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"Input details: {input_details}")
    print(f"Output details: {output_details}")

    # Test with sample input
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
    print("-" * 50)

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

        input_ids = encoding['input_ids'].astype(np.int32)
        attention_mask = encoding['attention_mask'].astype(np.int32)

        # Set inputs
        interpreter.set_tensor(input_details[0]['index'], input_ids)
        interpreter.set_tensor(input_details[1]['index'], attention_mask)

        # Run inference
        interpreter.invoke()

        # Get output
        output = interpreter.get_tensor(output_details[0]['index'])
        predicted_idx = np.argmax(output[0])
        predicted_label = label_names[predicted_idx]
        confidence = output[0][predicted_idx]

        status = "OK" if predicted_label == expected else "FAIL"
        print(f"{status} | '{text[:40]}...' -> {predicted_label} ({confidence:.3f}) [expected: {expected}]")

# ============================================
# MAIN
# ============================================

def main():
    print("=" * 50)
    print("TFLite Model Conversion")
    print("=" * 50)

    # Load tokenizer
    print("\nLoading tokenizer...")
    tokenizer = MobileBertTokenizer.from_pretrained(CONFIG['model_name'])

    # Convert from PyTorch to TensorFlow
    print("\nConverting PyTorch model to TensorFlow...")
    model = convert_pytorch_to_tf()

    # Convert to TFLite (default optimization)
    print("\nConverting to TFLite...")
    tflite_path = convert_to_tflite(model, tokenizer)

    # Try quantized version
    print("\nAttempting INT8 quantization...")
    convert_to_tflite_quantized(model, tokenizer)

    # Save vocabulary
    print("\nSaving vocabulary...")
    save_vocab(tokenizer)

    # Test the model
    test_tflite_model(tflite_path, tokenizer)

    print("\n" + "=" * 50)
    print("Conversion complete!")
    print("=" * 50)
    print("\nNext steps:")
    print("1. Copy intent_model.tflite to neurix/assets/models/")
    print("2. Copy vocab.txt to neurix/assets/models/")
    print("3. Update pubspec.yaml to include assets")
    print("4. Implement IntentClassifierService in Flutter")

if __name__ == '__main__':
    main()
