# Model Architecture Recommendation

## Goal: 95-99% Accuracy for Intent Classification

---

## Recommended Model: **DistilBERT** (Fine-tuned)

### Why DistilBERT?

| Factor | DistilBERT | LSTM | CNN | MobileBERT |
|--------|------------|------|-----|------------|
| Accuracy Potential | 95-99% | 85-92% | 82-90% | 93-97% |
| Model Size | ~250MB | ~50MB | ~30MB | ~100MB |
| Inference Speed | Medium | Fast | Fast | Fast |
| Context Understanding | Excellent | Good | Limited | Very Good |
| Training Data Needed | Medium | High | High | Medium |

### Model Comparison for Your Use Case:

#### Option 1: DistilBERT (Recommended for highest accuracy)
- **Base**: `distilbert-base-uncased`
- **Size**: ~250MB (TFLite quantized: ~65MB)
- **Accuracy**: 95-99%
- **Pros**: Best semantic understanding, handles variations well
- **Cons**: Larger size, slower inference

#### Option 2: MobileBERT (Best balance)
- **Base**: `google/mobilebert-uncased`
- **Size**: ~100MB (TFLite quantized: ~25MB)
- **Accuracy**: 93-97%
- **Pros**: Designed for mobile, good accuracy
- **Cons**: Slightly lower accuracy than DistilBERT

#### Option 3: TinyBERT (Smallest size)
- **Base**: `huawei-noah/TinyBERT_General_4L_312D`
- **Size**: ~60MB (TFLite quantized: ~15MB)
- **Accuracy**: 90-95%
- **Pros**: Very small, fast inference
- **Cons**: May miss edge cases

---

## My Recommendation: **MobileBERT with INT8 Quantization**

For your use case (on-device Flutter app), I recommend:

```
Model: MobileBERT
Quantization: INT8 (Post-training quantization)
Final Size: ~25-30MB
Expected Accuracy: 94-97%
Inference Time: ~50-100ms on modern phones
```

### Why MobileBERT over DistilBERT?
1. **Designed for mobile** - optimized architecture
2. **4x faster inference** than DistilBERT
3. **4x smaller** after quantization
4. **Still achieves 95%+ accuracy** with good training data

---

## Training Configuration

### Hyperparameters (Recommended)

```python
# Model Configuration
MODEL_NAME = "google/mobilebert-uncased"
MAX_LENGTH = 64  # Max tokens (your inputs are short)
NUM_LABELS = 6   # Number of classes

# Training Configuration
BATCH_SIZE = 32
LEARNING_RATE = 2e-5
NUM_EPOCHS = 5
WARMUP_STEPS = 500
WEIGHT_DECAY = 0.01

# Data Split
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15
```

### Training Strategy

1. **Use class weights** - Handle imbalanced classes
2. **Data augmentation** - Synonym replacement, random insertion
3. **Early stopping** - Monitor validation loss
4. **Learning rate scheduling** - Linear warmup + decay

---

## Accuracy Boosting Techniques

### 1. Data Augmentation
```python
# Techniques to increase training data variety:
- Synonym replacement (keys -> wallet, car keys)
- Random word swap (I put keys -> I keys put)
- Random insertion (I put keys -> I put my keys)
- Back-translation (English -> Hindi -> English)
```

### 2. Ensemble (Optional for 99% accuracy)
```
Train 3 models with different seeds
Average predictions
Can boost accuracy by 1-2%
```

### 3. Confidence Thresholding
```python
# If model confidence < 0.7, classify as "unclear"
# This reduces false positives
if max_probability < 0.7:
    return "unclear"
```

---

## Expected Results with Good Training Data

| Samples per Class | Expected Accuracy |
|-------------------|-------------------|
| 500 | 88-92% |
| 1000 | 92-95% |
| 1500 | 94-97% |
| 2000 | 95-98% |
| 3000+ | 97-99% |

**With 1500-2000 samples per class and MobileBERT, you should achieve 95-97% accuracy.**

---

## Class-Specific Considerations

| Class | Difficulty | Notes |
|-------|------------|-------|
| `save` | Medium | Many variations, context-dependent |
| `search` | Easy | Usually has question words |
| `reminder` | Easy | Has clear keywords (remind, reminder) |
| `cancel_all` | Easy | Limited patterns, easy to learn |
| `cancel_specific` | Medium | Need to distinguish from cancel_all |
| `unclear` | Hard | Catch-all, needs diverse examples |

### Confusion Matrix Concerns:
- `save` vs `search` - "My keys" could be either
- `cancel_all` vs `cancel_specific` - Need clear distinction
- `unclear` - Should catch incomplete/random input

---

## Training Pipeline

```
1. Load pre-trained MobileBERT
2. Add classification head (6 classes)
3. Freeze base layers (first 2 epochs)
4. Unfreeze and fine-tune all layers (remaining epochs)
5. Apply post-training INT8 quantization
6. Convert to TFLite format
7. Test on mobile device
```
