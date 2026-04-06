# Overwhisper Documentation

## Overview

**Overwhisper** is a native macOS menu bar application that provides voice-to-text transcription using local AI (WhisperKit) with an optional cloud API fallback (OpenAI). The app captures audio via global hotkeys, transcribes speech to text, and automatically inserts the transcription at the cursor position.

### Key Features

- **Global Hotkey Support**: Push-to-talk and toggle modes
- **Local AI Transcription**: Uses WhisperKit (Apple Silicon optimized)
- **Cloud Fallback**: Optional OpenAI API integration
- **Floating Overlay**: Real-time recording indicator with audio waveform
- **Auto-Insert**: Direct text insertion via clipboard + synthetic paste
- **Auto-Updates**: Sparkle framework for automatic updates

---

## Architecture

### Technology Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9 |
| Platform | macOS 14.0+ (Sonoma) |
| UI Framework | SwiftUI + AppKit (hybrid) |
| Audio | AVAudioEngine, CoreAudio, AudioToolbox |
| AI/ML | WhisperKit |
| Dependencies | HotKey, Sparkle |

### Project Structure

```
Overwhisper/
├── App/
│   ├── OverwhisperApp.swift       # App entry point
│   ├── AppDelegate.swift          # Main coordinator
│   ├── AppState.swift             # Global state management
│   └── CrashReporter.swift        # Crash reporting
├── Audio/
│   └── AudioRecorder.swift        # Recording & audio processing
├── Hotkey/
│   └── HotkeyManager.swift        # Global hotkey handling
├── Transcription/
│   ├── TranscriptionEngine.swift  # Protocol definition
│   ├── WhisperKitEngine.swift     # Local transcription
│   ├── OpenAIEngine.swift         # Cloud API
│   └── ModelManager.swift         # Model download/management
├── Output/
│   └── TextInserter.swift         # Text insertion via clipboard
├── UI/
│   ├── MenuBarIcon.swift          # Menu bar icon
│   ├── OnboardingView.swift       # First-run onboarding
│   ├── OverlayView.swift          # Recording overlay UI
│   ├── OverlayWindow.swift        # Floating window
│   ├── SettingsView.swift         # Settings interface
│   ├── ModelSelectionView.swift   # Model browser
│   └── TranscriptionHistoryView.swift # History management
├── Utils/
│   ├── SystemInfo.swift           # System detection
│   ├── CacheManager.swift         # Cache & cleanup
│   └── AppLogger.swift            # Logging
└── Resources/
    └── Assets.xcassets/
```

### Core Data Flow

1. **HotkeyManager** detects global hotkey press → notifies AppDelegate
2. **AppDelegate** starts **AudioRecorder** (records 16kHz mono WAV)
3. **OverlayWindow** shows recording indicator with real-time waveform
4. On stop, audio file passed to **TranscriptionEngine** (WhisperKit or OpenAI)
5. **TextInserter** pastes result at cursor via clipboard + synthetic Cmd+V

---

## Installation

### Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (for optimal WhisperKit performance)
- Microphone access
- Accessibility permission (for text insertion)

### Build from Source

Using Just (recommended):
```bash
just build          # Debug build
just build-release  # Release build
just run            # Run debug build
```

Using Swift Package Manager:
```bash
swift build                    # Debug build
swift build -c release         # Release build
swift run Overwhisper          # Run debug build
```

Using Xcode:
```bash
open Package.swift             # Open in Xcode
# Or
open Overwhisper.xcodeproj     # Open Xcode project
```

---

## Configuration

### Settings

Access settings via the menu bar icon → Settings...

#### General Tab
- **Hotkeys**: Configure Toggle (⌥Space) and Push-to-Talk (⌥⇧Space)
- **Overlay Position**: Choose where the recording indicator appears
- **Startup**: Start at login option

#### Transcription Tab
- **Current Engine**: Visual indicator showing Local or Cloud
- **Language**: Auto-detect or manual selection
- **Translate to English**: Option for multilingual models
- **Custom Vocabulary**: Add names/terms that get misspelled
- **Cloud API**: OpenAI Whisper API configuration
- **Local Model**: Manage downloaded models

#### Output Tab
- **Microphone**: Select input device
- **Mute system audio**: While recording
- **Recording duration limit**: Auto-stop after X seconds
- **Output**: Copy to clipboard option
- **Feedback**: Sounds and notifications
- **Transcription History**: Browse, search, export, favorite
- **Auto-Save**: Save to daily log files

#### Smart Tab
- **Auto-detect silence**: Stop recording after silence
- **Voice Activity Detection (VAD)**: Filter background noise
- **Auto-punctuation**: Capitalize and add periods
- **Profanity filter**: Mask inappropriate language

---

## Usage

### Basic Usage

1. **Start Recording**:
   - Press `⌥Space` (Toggle mode) or hold `⌥⇧Space` (Push-to-Talk)
   - The overlay window appears with a pulsing indicator

2. **Speak**: Talk clearly into your microphone

3. **Stop Recording**:
   - Press `⌥Space` again (Toggle) or release keys (Push-to-Talk)
   - Overlay shows "Transcribing..."

4. **Text Insertion**: Transcription automatically appears at cursor

### Recording Modes

**Toggle Mode (⌥Space)**:
- Press once to start recording
- Press again to stop and transcribe

**Push-to-Talk (⌥⇧Space)**:
- Hold to record
- Release to stop and transcribe

### Overlay Window

The floating overlay shows:
- Recording indicator (pulsing blue dot)
- Recording duration (0:00.0)
- Audio waveform visualization

**Click the indicator** to stop recording manually.

**Drag the window** to reposition it during recording.

---

## Features

### Smart Features

#### Auto-Silence Detection
Automatically stops recording after a specified period of silence (1-10 seconds). Useful when you finish speaking but forget to stop recording.

#### Voice Activity Detection (VAD)
Filters out background noise and only transcribes when speech is detected. Reduces false transcriptions from ambient sounds.

#### Auto-Punctuation
Automatically:
- Capitalizes first letter of sentences
- Adds periods at the end
- Capitalizes after sentence endings (.!?)

#### Profanity Filter
Masks inappropriate language with asterisks (***).

### Transcription History

Access full transcription history with:
- **Search**: Filter by text or tags
- **Favorites**: Star important transcriptions
- **Tags**: Organize with custom tags
- **Export**: Export to TXT, Markdown, or JSON
- **Auto-save**: Daily log files in Documents folder

### Model Management

**Auto-Detection**: The app automatically selects the best model based on your Mac's specs:
- 16GB+ RAM: Large v3 Turbo (Apple Silicon) or Large v3 (Intel)
- 8GB+ RAM: Medium
- 4GB+ RAM: Small
- Lower: Base or Tiny

**Available Models**:
| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| Tiny | ~75MB | Fastest | Basic |
| Base | ~150MB | Very Fast | Good |
| Small | ~500MB | Fast | Very Good |
| Medium | ~1.5GB | Moderate | Excellent |
| Large v3 | ~3GB | Slower | Best |
| Large v3 Turbo | ~1.6GB | Fast | Excellent |

---

## Permissions

### Required Permissions

1. **Microphone**: For recording audio
   - Requested on first launch
   - Can be changed in System Settings → Privacy & Security → Microphone

2. **Accessibility**: For global hotkeys and text insertion
   - Requested during onboarding
   - Required for: hotkey detection, clipboard access, simulating paste
   - Enable in System Settings → Privacy & Security → Accessibility

### Checking Permissions

Settings → General → "Check Accessibility Permission" button

---

## Advanced

### Auto-Save File Format

When auto-save is enabled, transcriptions are saved to:
```
~/Documents/Overwhisper_YYYY-MM-DD.txt
```

Format:
```
[14:30:25] This is a transcription example.

[14:32:10] Another transcription here.
```

### Cache Management

The app automatically:
- Cleans temp files older than 7 days
- Performs emergency cleanup if cache exceeds 500MB
- Removes crashed recording files after 5 minutes

### Crash Recovery

If the app crashes during recording:
1. Recording file is preserved
2. On next launch, the file is automatically transcribed
3. User is notified of the recovery

---

## Troubleshooting

### Common Issues

**"Accessibility permission needed"**
- Go to System Settings → Privacy & Security → Accessibility
- Add Overwhisper to the list
- Restart the app

**"Model not downloaded"**
- Go to Settings → Transcription → Local Model
- Click "Change Model..." and download a model
- Or let the app auto-download during onboarding

**"Recording failed"**
- Check microphone permission
- Try selecting a different microphone in Settings → Output
- Reset audio engine: Settings → Output → reselect microphone

**Hotkeys not working**
- Ensure accessibility permission is granted
- Check if hotkeys conflict with other apps
- Try resetting to defaults in Settings → General

### Debug Mode

Enable debug mode to see detailed logs:
- Settings → General → Debug Mode toggle
- View logs in Settings → Debug tab
- Logs include: transcription history, audio levels, model status

---

## API Reference

### TranscriptionEngine Protocol

```swift
protocol TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String
}
```

Implementations:
- `WhisperKitEngine`: Local transcription
- `OpenAIEngine`: Cloud API transcription

### AudioRecorder

Key properties:
- `currentLevel: Float` - Real-time audio level (0-1)
- `isRecording: Bool` - Recording state
- `isVoiceDetected: Bool` - VAD state

Methods:
- `startRecording()` - Begin recording
- `stopRecording()` - Stop and return audio URL
- `cancelRecording()` - Cancel and delete audio

### AppState

Central state management:
- Recording state
- Settings persistence
- Transcription history
- Model download progress

---

## Contributing

### Development Setup

1. Clone the repository
2. Open in Xcode 15.0+
3. Build and run (Cmd+R)

### Code Style

- Use `@MainActor` for UI-related classes
- Prefer `ObservableObject` + `@Published` for reactive state
- Use `async/await` for asynchronous operations
- Log via `AppLogger` (structured logging with OSLog)

### Adding Features

1. **New Setting**:
   - Add `@Published` property to `AppState` with `didSet` persistence
   - Add UI in appropriate section of `SettingsView`
   - Load value in `AppState.init()`
   - Add to `resetToDefaults()` if applicable

2. **New Hotkey**:
   - Add property to `AppState` (see existing examples)
   - Register in `HotkeyManager`
   - Handle in `AppDelegate.handleHotkeyEvent()`
   - Add UI using `HotkeyRecorderView`

3. **New Transcription Feature**:
   - Modify `WhisperKitEngine.transcribe()` or add post-processing
   - Add setting in `AppState` if user-configurable
   - Add UI in `SmartFeaturesSettingsView`

---

## License

Overwhisper is proprietary software. All rights reserved.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax
- [HotKey](https://github.com/soffes/HotKey) by Sam Soffes
- [Sparkle](https://sparkle-project.org/) for auto-updates

---

## Support

For issues and inquiries:
- GitHub: [github.com/OverseedAI/overwhisper](https://github.com/OverseedAI/overwhisper)
- Website: [overseed.ai](https://overseed.ai/)
- X (Twitter): [@_halshin](https://x.com/_halshin)

---

**Version**: 1.1.5  
**Last Updated**: 2026-04-04
