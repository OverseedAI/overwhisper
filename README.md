# Overwhisper

A native macOS menu bar app for voice transcription using local AI (WhisperKit) with optional cloud API fallback.

## Features

- **Global Hotkeys**: Configurable system-wide hotkeys for triggering recording
- **Two Recording Modes**: Push-to-talk (hold to record) or Toggle (press to start/stop)
- **Local Transcription**: Uses WhisperKit for on-device transcription with Apple Silicon optimization
- **Cloud Fallback**: Optional OpenAI Whisper API integration for fallback or as primary engine
- **Visual Overlay**: Floating recording indicator with audio waveform visualization
- **Direct Text Insertion**: Transcribed text is automatically typed at your cursor position

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended for best WhisperKit performance
- Microphone access permission
- Accessibility permission (for global hotkeys and text insertion)

## Building

### Using Swift Package Manager

```bash
cd Overwhisper
swift build
```

### Using Xcode

1. Open the project folder in Xcode
2. Select Product > Build (⌘B)
3. Run with Product > Run (⌘R)

## Setup

1. **Launch the app** - Overwhisper will appear in your menu bar
2. **Grant Permissions**:
   - Microphone: Required for audio recording
   - Accessibility: Required for global hotkeys and text insertion
3. **Configure Hotkey**: Open Settings (⌘,) and set your preferred hotkey
4. **Choose Model**: Select a WhisperKit model size based on your needs:
   - **Tiny/Base**: Fastest, lower accuracy
   - **Small**: Good balance
   - **Medium/Large**: Best accuracy, slower

## Usage

1. Focus on any text input field (Notes, browser, IDE, etc.)
2. Press your configured hotkey
3. Speak clearly
4. Release the hotkey (push-to-talk) or press again (toggle mode)
5. Wait for transcription
6. Text is automatically inserted at your cursor

## Settings

### General
- **Hotkey**: Global keyboard shortcut to trigger recording
- **Mode**: Push-to-talk or Toggle
- **Overlay Position**: Where the recording indicator appears
- **Start at Login**: Auto-launch on system startup

### Transcription
- **Engine**: WhisperKit (local) or OpenAI API
- **Model**: WhisperKit model size (tiny to large)
- **Language**: Auto-detect or specify language
- **Cloud Fallback**: Use OpenAI API if local transcription fails

### Output
- **Sound**: Play completion sound
- **Notifications**: Show error notifications

## Architecture

```
Overwhisper/
├── App/
│   ├── OverwhisperApp.swift    # Entry point
│   ├── AppDelegate.swift        # Menu bar and coordination
│   └── AppState.swift           # Global state management
├── Audio/
│   └── AudioRecorder.swift      # AVAudioEngine recording
├── Hotkey/
│   └── HotkeyManager.swift      # Global hotkey handling
├── Transcription/
│   ├── TranscriptionEngine.swift # Protocol
│   ├── WhisperKitEngine.swift   # Local AI transcription
│   ├── OpenAIEngine.swift       # Cloud API transcription
│   └── ModelManager.swift       # Model downloading/management
├── Output/
│   └── TextInserter.swift       # Clipboard + paste insertion
└── UI/
    ├── OverlayWindow.swift      # Floating NSPanel
    ├── OverlayView.swift        # SwiftUI recording animation
    └── SettingsView.swift       # Settings interface
```

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Local Whisper transcription
- [HotKey](https://github.com/soffes/HotKey) - Global hotkey handling

## Privacy

- All audio processing happens locally on your device when using WhisperKit
- Audio files are temporary and deleted after transcription
- OpenAI API key is stored securely in macOS Keychain
- No data is collected or transmitted except when using the OpenAI API option

## License

MIT License
