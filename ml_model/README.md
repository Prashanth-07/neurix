# Neurix Intent Classification Model

## Overview
Custom intent classification model for Neurix app to replace LLM-based intent detection.

## Classes (6 labels)
1. `save` - Store information to memory
2. `search` - Find/retrieve information
3. `reminder` - Create a new reminder
4. `cancel_all` - Cancel all reminders
5. `cancel_specific` - Cancel a specific reminder
6. `unclear` - Ambiguous or incomplete input

## Folder Structure
```
ml_model/
├── data/
│   ├── train/           # Training data (70%)
│   │   └── intent_train.csv
│   ├── validation/      # Validation data (15%)
│   │   └── intent_val.csv
│   └── test/            # Test data (15%)
│       └── intent_test.csv
├── models/              # Trained model files
│   ├── intent_model.tflite
│   └── tokenizer/
├── scripts/             # Training scripts
│   └── train_model.py
└── README.md
```

## Data Format
CSV with columns: `text`, `label`

Example:
```csv
text,label
I put my keys in the drawer,save
Where are my keys?,search
Remind me to drink water in 5 minutes,reminder
Cancel all my reminders,cancel_all
Stop my water reminder,cancel_specific
Hello,unclear
```

## Target Accuracy: 95-99%

## Recommended Sample Counts (per class)
- Minimum: 800-1000 samples per class
- Recommended: 1500-2000 samples per class
- Total dataset: ~9000-12000 samples

## Data Split
- Training: 70%
- Validation: 15%
- Test: 15%

## Model Architecture
- Base: DistilBERT (distilbert-base-uncased) - fine-tuned
- Alternative: MobileBERT for smaller size
- Deployment: TensorFlow Lite (TFLite) for on-device inference
