# Overwhisper

A native macOS menu bar app for voice transcription. Press a global hotkey, speak, and the text is typed at your cursor. Runs locally on-device by default (WhisperKit or Parakeet), with optional OpenAI cloud transcription.

## Download & Install

1. Grab the latest DMG from the [releases page](https://github.com/OverseedAI/overwhisper/releases/latest) — `Overwhisper-X.Y.Z.dmg`.
2. Open the DMG and drag **Overwhisper.app** into `/Applications`.
3. Launch it from Applications (or Spotlight). The first launch may show a Gatekeeper prompt — the app is signed and notarized, so just click **Open**.
4. Grant permissions when prompted:
   - **Microphone** — required for recording.
   - **Accessibility** — required for global hotkeys and pasting text at the cursor.
5. The icon appears in the menu bar (no dock icon). Click it to open Settings and pick a hotkey + model.

Updates are delivered automatically via Sparkle — you'll get a prompt when a new version is available.

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 or newer) — release builds are arm64-only
- Microphone + Accessibility permissions

## Features

- **Global hotkey** — configurable system-wide shortcut, push-to-talk or toggle.
- **Local transcription** — choose between [WhisperKit](https://github.com/argmaxinc/WhisperKit) or [Parakeet](https://github.com/FluidInference/FluidAudio) (via FluidAudio), both running on-device on Apple Silicon.
- **Cloud option** — OpenAI Whisper API as primary engine or fallback.
- **Recording overlay** — floating indicator with live waveform; configurable position.
- **Cursor-aware paste** — transcribed text is inserted wherever you're typing.
- **Auto-updates** — Sparkle handles version checks and installs.

## Usage

1. Focus any text field (Notes, browser, Slack, your IDE, etc.).
2. Press the configured hotkey.
3. Speak.
4. Release the hotkey (push-to-talk) or press it again (toggle).
5. The transcription is pasted at the cursor.

## Settings

- **General** — hotkey, recording mode, overlay position, start at login.
- **Transcription** — engine (WhisperKit / Parakeet / OpenAI), model size, language, cloud fallback.
- **Output** — completion sound, error notifications.
- **Debug** — audio playback, logs.

## Building from Source

Requires Xcode 15+ and the Swift toolchain.

```bash
just build          # debug build
just run            # run debug build
just build-release  # release build
just bundle         # produce Overwhisper.app
```

Or directly with SwiftPM:

```bash
swift build
swift run Overwhisper
```

For Xcode: `open Package.swift` (or `open Overwhisper.xcodeproj`).

## Architecture

Menu bar app with no dock presence. `AppDelegate` coordinates the components:

```
Overwhisper/
├── App/
│   ├── OverwhisperApp.swift     # SwiftUI entry point
│   ├── AppDelegate.swift        # Menu bar + component coordination
│   ├── AppState.swift           # Observable state, @AppStorage settings
│   └── CrashReporter.swift
├── Audio/
│   └── AudioRecorder.swift      # AVAudioEngine, 16kHz mono WAV
├── Hotkey/
│   └── HotkeyManager.swift      # Global hotkey via HotKey lib
├── Transcription/
│   ├── TranscriptionEngine.swift  # Protocol
│   ├── WhisperKitEngine.swift     # Local (WhisperKit)
│   ├── ParakeetEngine.swift       # Local (FluidAudio / Parakeet)
│   ├── OpenAIEngine.swift         # Cloud (OpenAI API)
│   └── ModelManager.swift         # Model download / cache management
├── Output/
│   └── TextInserter.swift       # Clipboard + synthetic Cmd+V
├── UI/
│   ├── OverlayWindow.swift      # Floating NSPanel
│   ├── OverlayView.swift        # Recording animation
│   ├── SettingsView.swift       # Tabbed settings
│   ├── OnboardingView.swift
│   ├── MenuBarIcon.swift
│   └── DebugAudioPlayer.swift
├── Logging/
└── Resources/
```

### Recording flow

1. `HotkeyManager` detects the global hotkey and notifies `AppDelegate`.
2. `AudioRecorder` captures mic input (AVAudioEngine, 16 kHz mono WAV).
3. `OverlayWindow` displays the recording indicator with a live waveform.
4. On stop, the WAV is handed to the selected `TranscriptionEngine`.
5. `TextInserter` pastes the result via clipboard + synthetic Cmd+V.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — local Whisper transcription
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet engine
- [HotKey](https://github.com/soffes/HotKey) — global hotkey handling
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-updates

## Privacy

- Audio stays on-device when using WhisperKit or Parakeet.
- Recordings are written to a temp file and deleted right after transcription.
- The OpenAI API key (if you use one) is stored in the macOS Keychain.
- Nothing is collected or transmitted except audio sent to OpenAI when that engine is selected.

## Support

Overwhisper is free and open source. If it saves you time, you can support development at [buymeacoffee.com/halshin](https://buymeacoffee.com/halshin).

## License

MIT — see [LICENSE](LICENSE).
