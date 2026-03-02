"""
Train a custom "Hey Neurix" wake word model for OpenWakeWord.

This script:
  1. Generates synthetic "hey neurix" audio using edge-tts + audio augmentation
  2. Loads real user enrollment recordings (if available)
  3. Generates hard negative samples (phonetically similar phrases, conversation, music)
  4. Extracts speech embeddings via OpenWakeWord's feature pipeline
  5. Trains a small classifier (FCN) on the embeddings
  6. Exports the model to ONNX format for Flutter

Usage:
  python tools/train_wake_word.py
  python tools/train_wake_word.py --enrollment-dir /path/to/enrollment

Output:
  assets/models/hey_neurix.onnx
"""

import os
import sys
import time
import wave
import struct
import random
import shutil
import asyncio
import tempfile
import argparse
import subprocess
import numpy as np

# ─── Configuration ───
SAMPLE_RATE = 16000

# Positive phrase variations (phonetic spellings for TTS diversity)
POSITIVE_VARIATIONS = [
    "hey neurix",
    "hey new rix",
    "hey nurix",
    "hey neuricks",
    "hey neuerix",
    "hey nuerix",
]

# Edge-TTS voices for diversity (male, female, different accents)
EDGE_VOICES = [
    # US English
    "en-US-GuyNeural",
    "en-US-JennyNeural",
    "en-US-AriaNeural",
    "en-US-DavisNeural",
    "en-US-AmberNeural",
    "en-US-AndrewNeural",
    "en-US-BrandonNeural",
    "en-US-ChristopherNeural",
    "en-US-CoraNeural",
    "en-US-ElizabethNeural",
    "en-US-EricNeural",
    "en-US-MichelleNeural",
    "en-US-MonicaNeural",
    "en-US-RogerNeural",
    "en-US-SteffanNeural",
    # UK English
    "en-GB-RyanNeural",
    "en-GB-SoniaNeural",
    "en-GB-ThomasNeural",
    "en-GB-LibbyNeural",
    # Australian English
    "en-AU-NatashaNeural",
    "en-AU-WilliamNeural",
    # Indian English
    "en-IN-NeerjaNeural",
    "en-IN-PrabhatNeural",
    # Other accents
    "en-IE-ConnorNeural",
    "en-IE-EmilyNeural",
    "en-ZA-LeahNeural",
    "en-ZA-LukeNeural",
]

# ─── Hard Negatives ───
# Phonetically similar phrases (most likely to cause false triggers)
HARD_NEGATIVE_PHRASES = [
    "hey matrix", "hey lyrics", "hey new tricks",
    "hey new rex", "hey neural", "hey neutrons",
    "hey patrick", "hey derek", "hey felix",
    "hey noorix", "hey numerix", "hey eurix",
    "hey new risk", "hey new mix", "hey new fix",
    "hey norex", "hey nurex", "hey nutrient",
    "hey google", "hey siri", "alexa",
    "hey jarvis", "hey cortana", "hey bixby",
    "hey there", "hey you", "hey buddy",
    "hey dude", "hey man", "hey girl",
    "hey wait", "hey look", "hey listen",
    "hey new", "hey no", "hey now",
]

# General conversation (should never trigger)
CONVERSATION_PHRASES = [
    "hello world", "good morning", "good night",
    "what time is it", "how are you", "nice to meet you",
    "turn off the lights", "play some music", "set a timer",
    "open the door", "call mom", "send a message",
    "the weather today", "remind me later", "take a note",
    "thank you very much", "excuse me please", "nevermind",
    "I need to go now", "see you later", "goodbye",
    "can you help me", "what is this", "where is that",
    "tell me a joke", "read my email", "check the news",
    "order some food", "book a ride", "find a restaurant",
    "what's the score", "who won the game", "turn up the volume",
    "I'm going to the store", "pick up the kids", "meeting at three",
    "the project is done", "let me think about it", "sounds good",
    "I agree with you", "that's interesting", "absolutely not",
    "maybe tomorrow", "I don't think so", "let's do it",
    "one two three four five", "a b c d e f g",
    "testing testing one two three",
    "the quick brown fox jumps over the lazy dog",
    "I love programming", "machine learning is great",
    "artificial intelligence", "deep neural network",
    "natural language processing", "computer vision",
]

# Short utterances and sounds (common false trigger sources)
SHORT_UTTERANCES = [
    "yes", "no", "ok", "sure", "right",
    "um", "uh", "hmm", "ah", "oh",
    "hi", "bye", "hey", "yo", "sup",
    "wow", "cool", "nice", "great", "fine",
    "stop", "go", "wait", "come", "help",
]

NUM_AUGMENTATIONS = 8  # augmentations per base positive sample
EPOCHS = 25
BATCH_SIZE = 64
LEARNING_RATE = 0.001
THRESHOLD = 0.5
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models")
OUTPUT_MODEL = os.path.join(OUTPUT_DIR, "hey_neurix.onnx")


def install_deps():
    """Install required Python packages."""
    required = {
        "openwakeword": "openwakeword",
        "torch": "torch",
        "edge_tts": "edge-tts",
        "scipy": "scipy",
        "imageio_ffmpeg": "imageio-ffmpeg",
    }
    missing = []
    for module, pip_name in required.items():
        try:
            __import__(module)
        except ImportError:
            missing.append(pip_name)
    if missing:
        print(f"[SETUP] Installing: {missing}")
        subprocess.check_call([sys.executable, "-m", "pip", "install"] + missing + ["-q"])
        print("[SETUP] Done")


async def generate_tts_clip(text, voice, output_path):
    """Generate an MP3 file using edge-tts."""
    import edge_tts
    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(output_path)


def mp3_to_wav_16k(mp3_path, wav_path):
    """Convert MP3 to 16kHz mono WAV using ffmpeg (via imageio-ffmpeg)."""
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        result = subprocess.run(
            [ffmpeg, "-y", "-i", mp3_path, "-ar", str(SAMPLE_RATE), "-ac", "1", "-f", "wav", wav_path],
            capture_output=True, timeout=30,
        )
        return result.returncode == 0 and os.path.exists(wav_path)
    except Exception as e:
        print(f"  Warning: MP3 conversion failed: {e}")
        return False


def load_wav(path):
    """Load a WAV file and return float32 numpy array at 16kHz."""
    from scipy.io import wavfile
    try:
        sr, data = wavfile.read(path)
    except Exception:
        return None
    if data.dtype == np.int16:
        data = data.astype(np.float32) / 32767.0
    elif data.dtype == np.int32:
        data = data.astype(np.float32) / 2147483647.0
    elif data.dtype == np.float64:
        data = data.astype(np.float32)
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    if sr != SAMPLE_RATE:
        from scipy.signal import resample
        num_samples = int(len(data) * SAMPLE_RATE / sr)
        data = resample(data, num_samples).astype(np.float32)
    return data


def load_pcm_file(path):
    """Load a raw Int16 PCM file saved by the enrollment screen."""
    try:
        with open(path, "rb") as f:
            raw = f.read()
        data = np.frombuffer(raw, dtype=np.int16)
        return data.astype(np.float32) / 32767.0
    except Exception as e:
        print(f"  Warning: could not load PCM file {path}: {e}")
        return None


def augment_audio(audio, sr=SAMPLE_RATE):
    """Apply random augmentation to an audio clip."""
    from scipy.signal import resample
    augmented = audio.copy()

    # Speed change (0.85x - 1.15x)
    speed = random.uniform(0.85, 1.15)
    if abs(speed - 1.0) > 0.01:
        augmented = resample(augmented, int(len(augmented) / speed)).astype(np.float32)

    # Pitch shift via resampling
    pitch = random.uniform(-3, 3)
    if abs(pitch) > 0.1:
        factor = 2.0 ** (pitch / 12.0)
        stretched = resample(augmented, int(len(augmented) / factor)).astype(np.float32)
        augmented = resample(stretched, len(augmented)).astype(np.float32)

    # Volume change (wider range)
    augmented *= random.uniform(0.3, 2.0)

    # Add noise (various levels)
    noise_level = random.uniform(0.0, 0.04)
    augmented += np.random.randn(len(augmented)).astype(np.float32) * noise_level

    # Random padding (simulate different positions in buffer)
    pad_before = int(random.uniform(0, 0.5) * sr)
    pad_after = int(random.uniform(0, 0.5) * sr)
    augmented = np.concatenate([
        np.zeros(pad_before, dtype=np.float32),
        augmented,
        np.zeros(pad_after, dtype=np.float32),
    ])

    # Random time masking (simulate partial word)
    if random.random() < 0.2:
        mask_len = int(random.uniform(0.05, 0.15) * len(augmented))
        mask_start = random.randint(0, max(0, len(augmented) - mask_len))
        augmented[mask_start:mask_start + mask_len] *= random.uniform(0.0, 0.1)

    return np.clip(augmented, -1.0, 1.0)


def generate_noise_clip(duration_sec=1.5, sr=SAMPLE_RATE):
    """Generate a random noise/silence clip."""
    n = int(duration_sec * sr)
    t = random.choice(["white", "pink", "silence", "hum"])
    if t == "white":
        return np.random.randn(n).astype(np.float32) * random.uniform(0.01, 0.1)
    elif t == "pink":
        # Simple pink noise approximation
        white = np.random.randn(n).astype(np.float32)
        b = np.array([0.049922035, -0.095993537, 0.050612699, -0.004709510])
        a = np.array([1.0, -2.494956002, 2.017265875, -0.522189400])
        from scipy.signal import lfilter
        pink = lfilter(b, a, white).astype(np.float32)
        return pink * random.uniform(0.01, 0.1)
    elif t == "hum":
        # 50/60Hz hum simulation
        freq = random.choice([50, 60, 100, 120])
        t_arr = np.linspace(0, duration_sec, n, dtype=np.float32)
        hum = np.sin(2 * np.pi * freq * t_arr) * random.uniform(0.01, 0.05)
        hum += np.random.randn(n).astype(np.float32) * 0.005
        return hum
    else:
        return np.random.randn(n).astype(np.float32) * 0.001


async def generate_training_data(tmp_dir, enrollment_dir=None):
    """Generate positive and negative audio clips."""
    positive_clips = []
    negative_clips = []

    # ─── Real enrollment recordings (highest priority) ───
    if enrollment_dir and os.path.exists(enrollment_dir):
        print("\n[STEP 0] Loading real enrollment recordings...")
        pcm_files = sorted([f for f in os.listdir(enrollment_dir) if f.endswith(".pcm")])
        real_count = 0
        for fname in pcm_files:
            audio = load_pcm_file(os.path.join(enrollment_dir, fname))
            if audio is not None and len(audio) > SAMPLE_RATE * 0.3:
                positive_clips.append(audio)
                real_count += 1
                # Heavy augmentation of real recordings (most valuable data)
                for _ in range(NUM_AUGMENTATIONS * 3):
                    positive_clips.append(augment_audio(audio))
        print(f"  Real recordings: {real_count} (+ {real_count * NUM_AUGMENTATIONS * 3} augmented)")

    # ─── Synthetic positive samples ───
    print("\n[STEP 1] Generating positive samples ('hey neurix')...")
    count = 0
    for voice in EDGE_VOICES:
        for phrase in POSITIVE_VARIATIONS:
            mp3_path = os.path.join(tmp_dir, f"pos_{count}.mp3")
            wav_path = os.path.join(tmp_dir, f"pos_{count}.wav")
            try:
                await generate_tts_clip(phrase, voice, mp3_path)
                if mp3_to_wav_16k(mp3_path, wav_path):
                    audio = load_wav(wav_path)
                    if audio is not None and len(audio) > SAMPLE_RATE * 0.3:
                        positive_clips.append(audio)
                        count += 1
            except Exception:
                pass

    print(f"  Base synthetic positive clips: {count}")

    # Augment synthetic positives
    synthetic_base = positive_clips[-count:] if count > 0 else []
    for clip in synthetic_base:
        for _ in range(NUM_AUGMENTATIONS):
            positive_clips.append(augment_audio(clip))
    print(f"  Total positive (after augmentation): {len(positive_clips)}")

    # ─── Hard negative samples (phonetically similar) ───
    print("\n[STEP 2a] Generating hard negative samples (phonetically similar)...")
    count = 0
    for voice in EDGE_VOICES[:12]:  # Use more voices for negatives
        for phrase in HARD_NEGATIVE_PHRASES:
            mp3_path = os.path.join(tmp_dir, f"hard_neg_{count}.mp3")
            wav_path = os.path.join(tmp_dir, f"hard_neg_{count}.wav")
            try:
                await generate_tts_clip(phrase, voice, mp3_path)
                if mp3_to_wav_16k(mp3_path, wav_path):
                    audio = load_wav(wav_path)
                    if audio is not None and len(audio) > SAMPLE_RATE * 0.3:
                        negative_clips.append(audio)
                        # Augment hard negatives more heavily
                        for _ in range(3):
                            negative_clips.append(augment_audio(audio))
                        count += 1
            except Exception:
                pass
    print(f"  Hard negative clips: {count} (+ augmented)")

    # ─── General conversation negatives ───
    print("\n[STEP 2b] Generating conversation negative samples...")
    count = 0
    conv_voices = EDGE_VOICES[:8]
    for voice in conv_voices:
        for phrase in CONVERSATION_PHRASES:
            mp3_path = os.path.join(tmp_dir, f"conv_neg_{count}.mp3")
            wav_path = os.path.join(tmp_dir, f"conv_neg_{count}.wav")
            try:
                await generate_tts_clip(phrase, voice, mp3_path)
                if mp3_to_wav_16k(mp3_path, wav_path):
                    audio = load_wav(wav_path)
                    if audio is not None and len(audio) > SAMPLE_RATE * 0.3:
                        negative_clips.append(audio)
                        negative_clips.append(augment_audio(audio))
                        count += 1
            except Exception:
                pass
    print(f"  Conversation negative clips: {count}")

    # ─── Short utterance negatives ───
    print("\n[STEP 2c] Generating short utterance negatives...")
    count = 0
    for voice in EDGE_VOICES[:6]:
        for phrase in SHORT_UTTERANCES:
            mp3_path = os.path.join(tmp_dir, f"short_neg_{count}.mp3")
            wav_path = os.path.join(tmp_dir, f"short_neg_{count}.wav")
            try:
                await generate_tts_clip(phrase, voice, mp3_path)
                if mp3_to_wav_16k(mp3_path, wav_path):
                    audio = load_wav(wav_path)
                    if audio is not None and len(audio) > SAMPLE_RATE * 0.2:
                        negative_clips.append(audio)
                        count += 1
            except Exception:
                pass
    print(f"  Short utterance clips: {count}")

    # ─── Noise clips ───
    print("\n[STEP 2d] Generating noise clips...")
    for _ in range(400):
        negative_clips.append(generate_noise_clip(
            duration_sec=random.uniform(1.0, 3.0)))
    print(f"  Noise clips: 400")

    print(f"\n  TOTAL positive: {len(positive_clips)}")
    print(f"  TOTAL negative: {len(negative_clips)}")

    return positive_clips, negative_clips


def ensure_oww_models():
    """Ensure OpenWakeWord's bundled models are available."""
    import openwakeword
    pkg_dir = os.path.dirname(openwakeword.__file__)
    models_dir = os.path.join(pkg_dir, "resources", "models")
    os.makedirs(models_dir, exist_ok=True)

    project_models = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models")

    for name in ["melspectrogram.onnx", "embedding_model.onnx"]:
        dest = os.path.join(models_dir, name)
        src = os.path.join(project_models, name)
        if not os.path.exists(dest) and os.path.exists(src):
            print(f"  Copying {name} to openwakeword resources...")
            shutil.copy2(src, dest)
        elif not os.path.exists(dest):
            import urllib.request
            url = f"https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/{name}"
            print(f"  Downloading {name}...")
            urllib.request.urlretrieve(url, dest)


def extract_embeddings(clips, label_name=""):
    """Extract OpenWakeWord embeddings from audio clips."""
    ensure_oww_models()
    from openwakeword.utils import AudioFeatures

    print(f"\n[STEP 3] Extracting {label_name} embeddings ({len(clips)} clips)...")
    F = AudioFeatures()

    # Pad/trim all clips to 2.0 seconds
    target_len = int(2.0 * SAMPLE_RATE)
    padded = []
    for clip in clips:
        if len(clip) >= target_len:
            padded.append(clip[:target_len])
        else:
            padded.append(np.concatenate([clip, np.zeros(target_len - len(clip), dtype=np.float32)]))

    audio_array = np.stack(padded)

    # OpenWakeWord expects 16-bit integer PCM
    audio_int16 = (audio_array * 32767).clip(-32768, 32767).astype(np.int16)
    print(f"  Audio shape: {audio_int16.shape} (int16)")

    features = F.embed_clips(x=audio_int16, batch_size=64, ncpu=1)
    print(f"  Embedding shape: {features.shape}")
    return features


def train_model(pos_features, neg_features):
    """Train a small FCN classifier on embeddings."""
    import torch
    import torch.nn as nn
    from torch.utils.data import TensorDataset, DataLoader

    print(f"\n[STEP 4] Training classifier...")
    print(f"  Positive: {pos_features.shape[0]}, Negative: {neg_features.shape[0]}")

    n_win = min(pos_features.shape[1], neg_features.shape[1])
    n_feat = pos_features.shape[2]
    pos_features = pos_features[:, :n_win, :]
    neg_features = neg_features[:, :n_win, :]
    print(f"  Input: ({n_win}, {n_feat})")

    X_pos = torch.tensor(pos_features, dtype=torch.float32)
    X_neg = torch.tensor(neg_features, dtype=torch.float32)
    y_pos = torch.ones(X_pos.shape[0], 1)
    y_neg = torch.zeros(X_neg.shape[0], 1)

    X = torch.cat([X_pos, X_neg])
    y = torch.cat([y_pos, y_neg])
    idx = torch.randperm(X.shape[0])
    X, y = X[idx], y[idx]

    # Split into train/val (90/10)
    split = int(0.9 * X.shape[0])
    X_train, X_val = X[:split], X[split:]
    y_train, y_val = y[:split], y[split:]

    loader = DataLoader(TensorDataset(X_train, y_train), batch_size=BATCH_SIZE, shuffle=True)

    # Slightly larger model for better discrimination
    model = nn.Sequential(
        nn.Flatten(),
        nn.Linear(n_win * n_feat, 128),
        nn.LayerNorm(128),
        nn.ReLU(),
        nn.Dropout(0.2),
        nn.Linear(128, 64),
        nn.LayerNorm(64),
        nn.ReLU(),
        nn.Dropout(0.1),
        nn.Linear(64, 32),
        nn.LayerNorm(32),
        nn.ReLU(),
        nn.Linear(32, 1),
        nn.Sigmoid(),
    )

    opt = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS)
    bce = nn.BCELoss(reduction="none")

    best_val_acc = 0.0
    best_state = None

    for epoch in range(EPOCHS):
        # Training
        model.train()
        total_loss = correct = total = 0
        for bx, by in loader:
            opt.zero_grad()
            pred = model(bx)
            # Weighted loss: balance positive vs negative
            w = torch.ones(by.shape[0])
            pos_frac = by.mean().item()
            w[by.flatten() == 1] = 1.0 / max(pos_frac, 0.1)
            w[by.flatten() == 0] = 1.0 / max(1.0 - pos_frac, 0.1)
            loss = (bce(pred, by) * w.unsqueeze(1)).mean()
            loss.backward()
            opt.step()
            total_loss += loss.item() * bx.shape[0]
            correct += ((pred > THRESHOLD).float() == by).sum().item()
            total += by.shape[0]

        # Validation
        model.eval()
        with torch.no_grad():
            val_pred = model(X_val)
            val_correct = ((val_pred > THRESHOLD).float() == y_val).sum().item()
            val_acc = val_correct / y_val.shape[0] * 100

            # Per-class accuracy
            val_pos_mask = y_val.flatten() == 1
            val_neg_mask = y_val.flatten() == 0
            if val_pos_mask.sum() > 0:
                val_tp = ((val_pred[val_pos_mask] > THRESHOLD).float()).sum().item()
                val_pos_acc = val_tp / val_pos_mask.sum().item() * 100
            else:
                val_pos_acc = 0.0
            if val_neg_mask.sum() > 0:
                val_tn = ((val_pred[val_neg_mask] <= THRESHOLD).float()).sum().item()
                val_neg_acc = val_tn / val_neg_mask.sum().item() * 100
            else:
                val_neg_acc = 0.0

        scheduler.step()

        print(f"  Epoch {epoch+1:2d}/{EPOCHS}: loss={total_loss/total:.4f} "
              f"train_acc={correct/total*100:.1f}% "
              f"val_acc={val_acc:.1f}% (pos:{val_pos_acc:.1f}% neg:{val_neg_acc:.1f}%)")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_state = {k: v.clone() for k, v in model.state_dict().items()}

    # Load best model
    if best_state is not None:
        model.load_state_dict(best_state)
        print(f"\n  Best validation accuracy: {best_val_acc:.1f}%")

    return model, n_win, n_feat


def export_onnx(model, n_win, n_feat):
    """Export trained model to ONNX."""
    import torch

    print(f"\n[STEP 5] Exporting ONNX...")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    torch.onnx.export(
        model.cpu().eval(),
        torch.rand(1, n_win, n_feat),
        OUTPUT_MODEL,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=11,
    )

    size = os.path.getsize(OUTPUT_MODEL)
    print(f"  Saved: {OUTPUT_MODEL} ({size/1024:.1f} KB)")

    # Verify
    import onnxruntime as ort
    sess = ort.InferenceSession(OUTPUT_MODEL)
    for i in sess.get_inputs():
        print(f"  Input:  name='{i.name}', shape={i.shape}")
    for o in sess.get_outputs():
        print(f"  Output: name='{o.name}', shape={o.shape}")

    test = np.random.randn(1, n_win, n_feat).astype(np.float32)
    result = sess.run(None, {"input": test})
    print(f"  Test inference (random): {result[0][0][0]:.4f}")


async def async_main():
    parser = argparse.ArgumentParser(description="Train Hey Neurix wake word model")
    parser.add_argument("--enrollment-dir", type=str, default=None,
                       help="Path to enrollment directory with .pcm files")
    args = parser.parse_args()

    start = time.time()
    print("=" * 60)
    print("  OpenWakeWord Training: 'Hey Neurix' (Enhanced)")
    print("=" * 60)

    install_deps()

    tmp_dir = tempfile.mkdtemp(prefix="wakeword_")
    print(f"\n[INFO] Temp dir: {tmp_dir}")
    if args.enrollment_dir:
        print(f"[INFO] Enrollment dir: {args.enrollment_dir}")

    try:
        pos_clips, neg_clips = await generate_training_data(
            tmp_dir, enrollment_dir=args.enrollment_dir)
        pos_feat = extract_embeddings(pos_clips, "positive")
        neg_feat = extract_embeddings(neg_clips, "negative")

        model, n_win, n_feat = train_model(pos_feat, neg_feat)
        export_onnx(model, n_win, n_feat)

        elapsed = time.time() - start
        print(f"\n{'=' * 60}")
        print(f"  Done! ({elapsed:.0f}s)")
        print(f"  Model: {OUTPUT_MODEL}")
        print(f"")
        print(f"  Rebuild Flutter app to use the new model.")
        print(f"{'=' * 60}")

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    asyncio.run(async_main())
