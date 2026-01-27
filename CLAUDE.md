# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
swift build                    # Debug build
swift build -c release         # Release build
swift run Overwhisper          # Run debug build
```

Or use the Justfile:
```bash
just build                     # Debug build
just run                       # Run app
just bundle                    # Create .app bundle
```

For Xcode: `open Package.swift` or `open Overwhisper.xcodeproj`

## Releasing

```bash
./scripts/bump-version.sh 1.0.24   # Updates version, commits, tags, pushes
```

This triggers the GitHub Actions workflow to build, notarize, and release a DMG.

## Architecture

**Menu bar app** - No dock icon, lives in the menu bar. Entry point is `AppDelegate` which coordinates all components.

### Core Flow
1. **HotkeyManager** detects global hotkey press → notifies AppDelegate
2. **AppDelegate** starts **AudioRecorder** (AVAudioEngine-based, 16kHz mono WAV)
3. **OverlayWindow** shows recording indicator with waveform
4. On stop, audio file passed to **TranscriptionEngine** (WhisperKit local or OpenAI cloud)
5. **TextInserter** pastes result at cursor via clipboard + synthetic Cmd+V

### Key Components

- **AppState** (`App/AppState.swift`): Observable state for all settings, persisted via `@AppStorage`
- **AudioRecorder** (`Audio/AudioRecorder.swift`): Handles mic input, device selection, format conversion
- **ModelManager** (`Transcription/ModelManager.swift`): Downloads/deletes WhisperKit models, scans multiple cache locations
- **TranscriptionEngine** protocol with two implementations: `WhisperKitEngine` (local) and `OpenAIEngine` (cloud)

### UI
- **OverlayWindow**: Floating NSPanel that appears during recording
- **SettingsView**: SwiftUI settings with tabs (General, Transcription, Output, Debug)

## Key Learnings

**AVAudioEngine device handling**: Don't call `AudioUnitSetProperty` to set the system default device - AVAudioEngine already handles this. Only set explicitly for user-selected non-default devices. See `LEARNINGS.md`.

## Dependencies

- **WhisperKit**: Local on-device transcription (Apple Silicon optimized)
- **HotKey**: Global keyboard shortcut handling
- **Sparkle**: Auto-updates
