# Learnings

## AVAudioEngine: Don't override system default device

**Problem:** Recording with the built-in MacBook microphone failed with error -10868 (`kAudioUnitErr_FormatNotSupported`), while external interfaces (e.g., Scarlett) worked fine.

**Root cause:** When using "System Default", the code was calling `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` to explicitly set the device to the default device ID. But AVAudioEngine already initializes its `inputNode` with the system default automatically. Re-setting it interfered with the engine's internal format negotiation.

**Fix:** Only call `AudioUnitSetProperty` when the user explicitly selects a non-default device. For system default, let AVAudioEngine handle it natively.

```swift
func applyInputDevice() throws {
    // If using system default, don't override - let AVAudioEngine use its default
    guard let targetDeviceID = selectedInputDeviceID else { return }

    // Only set device explicitly for user-selected devices
    // ...
}
```

**Lesson:** Don't override framework defaults unnecessarily. When the framework already does the right thing by default, explicitly setting the same value can cause problems rather than being a harmless no-op.
