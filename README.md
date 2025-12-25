# neurix

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


Neurix Application Overview
Neurix is a cross-platform personal memory management and AI-powered voice assistant built with Flutter. It allows users to store, manage, and search their personal memories through voice interactions.
🎯 What It Does
Voice-driven memory storage: Speak to save personal memories, notes, and information
AI-powered search: Ask questions and get contextual answers based on your stored memories
Offline-first design: Works without internet, syncs when online
Multi-platform: Runs on Android, iOS, Web, Windows, macOS, and Linux
🏗️ Technology Stack
Frontend: Flutter (Dart SDK 3.7.2)
Authentication: Firebase Auth with Google Sign-In
Database:
Local: SQLite (offline storage)
Cloud: Firestore (backup & sync)
AI: Groq API (llama3-8b-8192 model)
Voice: Speech-to-text + Text-to-speech
State Management: Provider pattern
📁 Project Structure
neurix/
├── lib/
│   ├── main.dart              # App entry point
│   ├── models/                # Data models (User, Memory)
│   ├── screens/               # UI screens (Login, Home, Voice)
│   ├── services/              # Business logic
│   │   ├── auth_service.dart
│   │   ├── voice_service.dart
│   │   ├── llm_service.dart
│   │   ├── sync_service.dart
│   │   ├── local_db_service.dart
│   │   └── cloud_db_service.dart
│   └── utils/                 # Constants & styling
├── android/ios/web/windows/   # Platform-specific code
└── pubspec.yaml               # Dependencies
⚡ Key Features
Authentication: Email/password + Google OAuth
Memory Management: Add timestamped memories via voice or text
Smart Search: AI analyzes your memory history to answer questions
Sync System: Automatic local/cloud synchronization with retry logic
Voice Interface: Two modes - "Add Memory" and "Search"
Insights: AI generates patterns and analysis from your memories
🔄 How It Works
Login → Firebase authenticates user
Voice Input → Speech-to-text captures your words
Processing → Either saves memory OR searches existing memories via AI
Response → Text-to-speech reads back confirmation/answers
Sync → Data stored locally (SQLite) and synced to cloud (Firestore)
🔑 Entry Point
The app starts at main.dart, which:
Initializes Firebase
Sets up state management providers
Routes to login or home screen based on auth status