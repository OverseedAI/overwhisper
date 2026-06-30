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

## Recording is coupled to the default OUTPUT device — use an input-only HAL unit

**Problem:** With a separate mic and speaker (e.g. Scarlett input + Bluetooth WH-1000XM6 output), recording would fail intermittently: the start sound cut off, the overlay flashed and vanished, and nothing got transcribed. Plain mic-only setups worked. The mic itself was healthy — the *output* device determined whether capture survived.

**Root cause:** `AVAudioEngine`'s render loop is clocked by its `outputNode`, which is bound to the system **default output device** — even when we only `installTap` on the input and never connect anything to the output. Starting the engine opens and clocks off that output device. A Bluetooth output is unstable (A2DP↔HFP profile switching, separate clock domain), so the moment the engine grabbed it the route collapsed and capture died. That's why the *speaker* selection broke a *recording* app.

**Fix:** Drop `AVAudioEngine` for capture. Use a `kAudioUnitSubType_HALOutput` audio unit in **input-only** mode (enable IO on input bus 1, disable output bus 0) and bind it explicitly to the chosen input device via `kAudioOutputUnitProperty_CurrentDevice`. No output/speaker device ever enters the graph, so the output selection can't affect recording. Note a HAL unit defaults `CurrentDevice` to the default *output* device, so the input device must **always** be bound explicitly (including for "System Default", resolved via `kAudioHardwarePropertyDefaultInputDevice`). See `AudioRecorder.makeInputUnit`.

**Lesson:** `AVAudioEngine` is a full-duplex graph; "I only want input" still drags in the default output device. When you need decoupled, device-pinned capture, go one layer down to a raw input AUHAL.
