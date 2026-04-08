# AGENTS.md

## Build Commands
```bash
just build        # Debug build (SPM)
just run          # Run app
just bundle       # Release build + create .app bundle
```

Xcode: `open Package.swift` or `open Overwhisper.xcodeproj`

## Release Process
1. `./scripts/bump-version.sh X.Y.Z` - Updates version in project.yml, commits, tags, pushes
2. GitHub Actions auto-triggers: builds → notarizes → creates DMG → updates appcast

## Architecture
- **Menu bar app** (LSUIElement=true, no dock icon)
- **Entry point**: AppDelegate coordinates: HotkeyManager → AudioRecorder → TranscriptionEngine → TextInserter
- **Transcription engines** (protocol-based):
  - `WhisperKitEngine` - Whisper local (via WhisperKit)
  - `ParakeetEngine` - NVIDIA Parakeet local (via FluidAudio)
  - `OpenAIEngine` - Cloud API
- **ModelManager**: Downloads/deletes WhisperKit models, scans multiple cache locations

## Version Sync (critical)
Version must be updated in 3 places:
1. `project.yml` → `MARKETING_VERSION`
2. `Overwhisper.xcodeproj/project.pbxproj` → `MARKETING_VERSION`
3. `Info.plist` → `CFBundleShortVersionString` (via GitHub Actions)

`scripts/bump-version.sh` handles #1-2; CI handles #3.

## Technical Notes
- **AVAudioEngine quirk**: Don't call `AudioUnitSetProperty` to set system default device. AVAudioEngine handles this automatically; overriding causes error -10868 (`kAudioUnitErr_FormatNotSupported`). Only set device explicitly for user-selected non-default devices. See `LEARNINGS.md`.

## File References
- `CLAUDE.md` - Claude Code guidance
- `LEARNINGS.md` - Technical learnings
