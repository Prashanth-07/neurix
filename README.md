# Neurix

A cross-platform AI-powered personal memory assistant built with Flutter. Save memories, set reminders, and search your personal knowledge base using natural voice commands.

## Features

### Voice-Driven Memory Management
- **Save Memories**: Speak to store personal notes, facts, and information
- **Search Memories**: Ask natural questions and get contextual answers from your stored memories
- **Semantic Search**: Uses vector embeddings for intelligent similarity-based retrieval

### Smart Reminders
- **One-Time Reminders**: "Remind me to call mom in 30 minutes"
- **Recurring Reminders**: "Remind me to drink water every 2 hours"
- **Static Time Reminders**: "Remind me to take medicine at 8 PM"
- **Voice Cancellation**: "Cancel all my reminders" or "Cancel the water reminder"

### On-Device AI Intent Classification
- Uses a custom-trained **MobileBERT** model running via **ONNX Runtime**
- Classifies user input into 6 intents:
  - `save` - Store new information
  - `search` - Retrieve information from memories
  - `reminder` - Create a new reminder
  - `cancel_all` - Cancel all reminders
  - `cancel_specific` - Cancel a specific reminder
  - `unclear` - Request clarification
- **70%+ confidence threshold** with fallback to unclear state
- Fully offline - no API calls for intent detection

### Confirmation Dialog
- Save and reminder intents show a confirmation dialog before execution
- TTS reads the action aloud
- Voice-enabled: Say "yes" to confirm, "no" to cancel
- Auto-confirms after 5 seconds if no response
- Search queries execute immediately without confirmation

### Persistent Voice Notification (Android)
- Always-on notification with quick action buttons
- **Speak**: Tap to start voice input
- **Add Memory**: Direct save mode
- **Search**: Direct search mode
- Works from notification shade without opening the app

### Offline-First Architecture
- **SQLite** for local storage with full offline functionality
- **Firestore** for cloud backup and cross-device sync
- Automatic sync when connectivity is restored

## Technology Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart SDK 3.6+) |
| Authentication | Firebase Auth + Google Sign-In |
| Local Database | SQLite (sqflite) |
| Cloud Database | Cloud Firestore |
| Intent Classification | MobileBERT (ONNX Runtime) |
| Embeddings | On-device vector generation |
| LLM Backend | Groq API (llama3-8b-8192) |
| Voice Input | speech_to_text |
| Voice Output | flutter_tts |
| Notifications | flutter_local_notifications |
| Background Tasks | android_alarm_manager_plus |
| State Management | Provider |

## Project Structure

```
neurix/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── models/
│   │   ├── user_model.dart          # User data model
│   │   ├── memory_model.dart        # Memory with embeddings
│   │   └── reminder_model.dart      # Reminder with scheduling
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart    # Login UI
│   │   │   └── register_screen.dart # Registration UI
│   │   ├── home_screen.dart         # Main voice interface
│   │   ├── all_memories_screen.dart # View/manage memories
│   │   ├── reminders_screen.dart    # View/manage reminders
│   │   ├── alarm_screen.dart        # Alarm trigger UI
│   │   └── voice_interaction_screen.dart
│   ├── services/
│   │   ├── auth_service.dart        # Firebase authentication
│   │   ├── local_db_service.dart    # SQLite operations
│   │   ├── cloud_db_service.dart    # Firestore operations
│   │   ├── sync_service.dart        # Local/cloud sync
│   │   ├── llm_service.dart         # Groq API integration
│   │   ├── intent_classifier_service.dart  # MobileBERT inference
│   │   ├── embedding_service.dart   # Vector embeddings
│   │   ├── reminder_service.dart    # Reminder scheduling
│   │   ├── notification_service.dart # Notifications & voice
│   │   └── alarm_helper_service.dart # Native alarm triggers
│   ├── widgets/
│   │   ├── confirmation_dialog.dart # Voice confirmation dialog
│   │   ├── floating_bubble.dart     # Overlay bubble
│   │   └── slide_to_stop.dart       # Alarm dismiss UI
│   └── utils/
│       └── constants.dart           # App constants & styling
├── assets/
│   ├── models/
│   │   ├── intent_model.onnx        # MobileBERT ONNX model
│   │   └── vocab.txt                # BERT vocabulary
│   └── sounds/                      # Alarm sounds
├── android/                         # Android platform code
├── ios/                             # iOS platform code
└── pubspec.yaml                     # Dependencies
```

## How It Works

### Voice Processing Flow

```
User speaks → Speech-to-Text → Intent Classification (MobileBERT)
                                        ↓
                ┌───────────────────────┼───────────────────────┐
                ↓                       ↓                       ↓
            [SAVE]                  [SEARCH]               [REMINDER]
                ↓                       ↓                       ↓
        Confirmation Dialog      Execute immediately    Confirmation Dialog
                ↓                       ↓                       ↓
        Save to SQLite          Semantic Search         Parse time/recurrence
        Generate embedding       + LLM Response          Schedule alarm
                ↓                       ↓                       ↓
        TTS: "Got it!"          TTS: Answer             TTS: "I'll remind you..."
```

### Intent Classification

The app uses a custom-trained MobileBERT model converted to ONNX format for on-device inference:

1. **Tokenization**: WordPiece tokenization using BERT vocabulary
2. **Inference**: ONNX Runtime processes input tensors
3. **Classification**: Softmax over 6 intent classes
4. **Confidence Check**: Falls back to "unclear" if confidence < 70%

### Reminder System

Reminders support multiple time formats:

| Format | Example | Type |
|--------|---------|------|
| Duration | "in 30 minutes" | One-time |
| Static time | "at 8 PM" | One-time |
| Recurring | "every 2 hours" | Recurring |

When triggered:
1. Device wakes up (screen on)
2. Alarm sound plays
3. Full-screen alarm UI appears
4. TTS speaks the reminder message
5. User dismisses with slide gesture

## Setup

### Prerequisites
- Flutter SDK 3.6+
- Firebase project with Authentication and Firestore
- Groq API key (for LLM responses)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/neurix.git
cd neurix
```

2. Install dependencies:
```bash
flutter pub get
```

3. Configure Firebase:
   - Create a Firebase project
   - Enable Email/Password and Google Sign-In authentication
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place in respective platform directories

4. Create `.env` file in project root:
```env
GROQ_API_KEY=your_groq_api_key_here
```

5. Run the app:
```bash
flutter run
```

### Android Setup

The following permissions are configured in `AndroidManifest.xml`:
- `RECORD_AUDIO` - Voice input
- `INTERNET` - API calls
- `POST_NOTIFICATIONS` - Notifications
- `SCHEDULE_EXACT_ALARM` - Reminder scheduling
- `RECEIVE_BOOT_COMPLETED` - Persist reminders across reboots
- `FOREGROUND_SERVICE` - Background operations

### iOS Setup

The following are configured in `Info.plist`:
- `NSSpeechRecognitionUsageDescription` - Speech recognition
- `NSMicrophoneUsageDescription` - Microphone access
- `UIBackgroundModes` - audio, fetch, remote-notification

## Usage

### Voice Commands

**Saving Memories:**
- "Remember that my WiFi password is abc123"
- "Save this: John's birthday is March 15th"
- "Note: The meeting room code is 4521"

**Searching Memories:**
- "What is my WiFi password?"
- "When is John's birthday?"
- "What was the meeting room code?"

**Setting Reminders:**
- "Remind me to call mom in 30 minutes"
- "Remind me to drink water every hour"
- "Remind me to take medicine at 9 PM"

**Canceling Reminders:**
- "Cancel all my reminders"
- "Cancel the water reminder"
- "Stop reminding me about medicine"

### UI Interaction

1. **Tap the microphone** to start voice input
2. **Speak your command** - transcription appears in real-time
3. **Confirmation dialog** appears for save/reminder actions
4. **Say "yes" or "no"** or wait for auto-confirm
5. **Response is spoken** via TTS

## ML Model

The intent classification model is a fine-tuned MobileBERT:

- **Base Model**: google/mobilebert-uncased
- **Training Data**: Custom dataset with 6 intent classes
- **Export Format**: ONNX (optimized for mobile)
- **Input**: Tokenized text (max 64 tokens)
- **Output**: 6-class probability distribution

### Model Files

Located in `assets/models/`:
- `intent_model.onnx` - MobileBERT ONNX model (~25MB)
- `vocab.txt` - BERT vocabulary file (~226K tokens)

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android | Fully supported | All features including persistent notification |
| iOS | Supported | No persistent notification (iOS limitation) |
| Web | Partial | No speech recognition |
| Windows | Partial | Limited voice features |
| macOS | Partial | Limited voice features |
| Linux | Partial | Limited voice features |

## License

This project is private and not published to pub.dev.

## Contributing

This is a personal project. For questions or suggestions, please open an issue.
