"""
Train a custom "Hey Neurix" wake word model for OpenWakeWord.

This script:
  1. Generates synthetic "hey neurix" audio using edge-tts + audio augmentation
  2. Generates negative samples (random phrases, noise)
  3. Extracts speech embeddings via OpenWakeWord's feature pipeline
  4. Trains a small classifier (FCN) on the embeddings
  5. Exports the model to ONNX format for Flutter

Usage:
  python tools/train_wake_word.py

Output:
  assets/models/hey_neurix.onnx  (drop-in replacement for hey_jarvis_v0.1.onnx)
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
import subprocess
import numpy as np

# ─── Configuration ───
SAMPLE_RATE = 16000
POSITIVE_VARIATIONS = [
    "hey neurix",
    "hey new rix",
    "hey nurix",
    "hey neuricks",
]
# Edge-TTS voices for diversity
EDGE_VOICES = [
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
    "en-GB-RyanNeural",
    "en-GB-SoniaNeural",
    "en-AU-NatashaNeural",
    "en-AU-WilliamNeural",
    "en-IN-NeerjaNeural",
    "en-IN-PrabhatNeural",
]
NEGATIVE_PHRASES = [
    "hey google", "hey siri", "alexa", "hey jarvis",
    "hey matrix", "hey lyrics", "hey new tricks",
    "hello world", "good morning", "what time is it",
    "turn off the lights", "play some music", "set a timer",
    "open the door", "call mom", "send a message",
    "the weather today", "remind me later", "take a note",
    "how are you", "nice to meet you", "thank you",
    "hey there", "excuse me", "nevermind",
    "hey patrick", "hey derek", "hey felix",
    "hey new rex", "hey neural", "hey neutrons",
]
NUM_AUGMENTATIONS = 6  # augmentations per base positive sample
EPOCHS = 15
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


def augment_audio(audio, sr=SAMPLE_RATE):
    """Apply random augmentation to an audio clip."""
    from scipy.signal import resample
    augmented = audio.copy()

    # Speed change (0.85x - 1.15x)
    speed = random.uniform(0.85, 1.15)
    if abs(speed - 1.0) > 0.01:
        augmented = resample(augmented, int(len(augmented) / speed)).astype(np.float32)

    # Pitch shift via resampling
    pitch = random.uniform(-2, 2)
    if abs(pitch) > 0.1:
        factor = 2.0 ** (pitch / 12.0)
        stretched = resample(augmented, int(len(augmented) / factor)).astype(np.float32)
        augmented = resample(stretched, len(augmented)).astype(np.float32)

    # Volume change
    augmented *= random.uniform(0.5, 1.5)

    # Add noise
    noise_level = random.uniform(0.0, 0.02)
    augmented += np.random.randn(len(augmented)).astype(np.float32) * noise_level

    # Random padding
    pad_before = int(random.uniform(0, 0.3) * sr)
    pad_after = int(random.uniform(0, 0.3) * sr)
    augmented = np.concatenate([
        np.zeros(pad_before, dtype=np.float32),
        augmented,
        np.zeros(pad_after, dtype=np.float32),
    ])

    return np.clip(augmented, -1.0, 1.0)


def generate_noise_clip(duration_sec=1.5, sr=SAMPLE_RATE):
    """Generate a random noise clip."""
    n = int(duration_sec * sr)
    t = random.choice(["white", "silence"])
    if t == "white":
        return np.random.randn(n).astype(np.float32) * random.uniform(0.01, 0.1)
    else:
        return np.random.randn(n).astype(np.float32) * 0.001


async def generate_training_data(tmp_dir):
    """Generate positive and negative audio clips using edge-tts."""
    positive_clips = []
    negative_clips = []

    # ─── Positive samples ───
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
            except Exception as e:
                pass  # Some voices may fail, that's OK

    print(f"  Base positive clips: {count}")

    # Augment
    base = list(positive_clips)
    for clip in base:
        for _ in range(NUM_AUGMENTATIONS):
            positive_clips.append(augment_audio(clip))
    print(f"  Total positive (after augmentation): {len(positive_clips)}")

    # ─── Negative samples ───
    print("\n[STEP 2] Generating negative samples...")
    count = 0
    # Use a subset of voices for negatives (faster)
    neg_voices = EDGE_VOICES[:6]
    for voice in neg_voices:
        for phrase in NEGATIVE_PHRASES:
            mp3_path = os.path.join(tmp_dir, f"neg_{count}.mp3")
            wav_path = os.path.join(tmp_dir, f"neg_{count}.wav")
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

    print(f"  TTS negative clips: {count}")

    # Add noise clips
    for _ in range(200):
        negative_clips.append(generate_noise_clip())
    print(f"  Total negative: {len(negative_clips)}")

    return positive_clips, negative_clips


def ensure_oww_models():
    """Ensure OpenWakeWord's bundled models are available."""
    import openwakeword
    pkg_dir = os.path.dirname(openwakeword.__file__)
    models_dir = os.path.join(pkg_dir, "resources", "models")
    os.makedirs(models_dir, exist_ok=True)

    # Use our already-downloaded models as source
    project_models = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models")

    for name in ["melspectrogram.onnx", "embedding_model.onnx"]:
        dest = os.path.join(models_dir, name)
        src = os.path.join(project_models, name)
        if not os.path.exists(dest) and os.path.exists(src):
            print(f"  Copying {name} to openwakeword resources...")
            shutil.copy2(src, dest)
        elif not os.path.exists(dest):
            # Download from GitHub
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

    # Pad/trim all clips to 2.0 seconds (gives ~16 embedding windows to match hey_jarvis)
    target_len = int(2.0 * SAMPLE_RATE)
    padded = []
    for clip in clips:
        if len(clip) >= target_len:
            padded.append(clip[:target_len])
        else:
            padded.append(np.concatenate([clip, np.zeros(target_len - len(clip), dtype=np.float32)]))

    audio_array = np.stack(padded)

    # OpenWakeWord expects 16-bit integer PCM, not float32
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

    loader = DataLoader(TensorDataset(X, y), batch_size=BATCH_SIZE, shuffle=True)

    model = nn.Sequential(
        nn.Flatten(),
        nn.Linear(n_win * n_feat, 64),
        nn.LayerNorm(64),
        nn.ReLU(),
        nn.Linear(64, 32),
        nn.LayerNorm(32),
        nn.ReLU(),
        nn.Linear(32, 1),
        nn.Sigmoid(),
    )

    opt = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)
    bce = nn.BCELoss(reduction="none")

    for epoch in range(EPOCHS):
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
        print(f"  Epoch {epoch+1:2d}/{EPOCHS}: loss={total_loss/total:.4f} acc={correct/total*100:.1f}%")

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
    print(f"  Test inference: {result[0][0][0]:.4f}")


async def async_main():
    start = time.time()
    print("=" * 60)
    print("  OpenWakeWord Training: 'Hey Neurix'")
    print("=" * 60)

    install_deps()

    tmp_dir = tempfile.mkdtemp(prefix="wakeword_")
    print(f"\n[INFO] Temp dir: {tmp_dir}")

    try:
        pos_clips, neg_clips = await generate_training_data(tmp_dir)
        pos_feat = extract_embeddings(pos_clips, "positive")
        neg_feat = extract_embeddings(neg_clips, "negative")

        model, n_win, n_feat = train_model(pos_feat, neg_feat)
        export_onnx(model, n_win, n_feat)

        elapsed = time.time() - start
        print(f"\n{'=' * 60}")
        print(f"  Done! ({elapsed:.0f}s)")
        print(f"  Model: {OUTPUT_MODEL}")
        print(f"")
        print(f"  Next: Update wake_word_service.dart _wwModelPath to")
        print(f"  'assets/models/hey_neurix.onnx' and rebuild.")
        print(f"{'=' * 60}")

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    asyncio.run(async_main())
