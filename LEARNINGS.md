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

### Follow-on gotchas from the AUHAL rewrite

- **Multi-channel client format needs an explicit channel layout.** `AVAudioFormat(commonFormat:sampleRate:channels:interleaved:)` returns **nil for >2 channels**, and even `AVAudioFormat(streamDescription:)` returns nil above stereo without a layout. The Scarlett Solo reports **4** input channels, so both failed silently → `deviceConfigurationFailed`. Fix: build the ASBD and attach an `AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channelCount)` when `channels > 2`.
- **A raw HAL unit exposes channels in device order, not mic-first.** Confirmed via a per-channel RMS probe: on the Scarlett, `ch0/ch1` carry the mic and `ch2/ch3` are silent monitor returns — so `channelMap = [0]` is correct here, but don't assume it's universal; channel 0 = physical input 1.
- **USB interfaces have real startup latency.** First input buffer arrived ~570ms after `AudioOutputUnitStart` on the Scarlett. Short recordings (sub-second taps) captured almost nothing → "silent" and dropped. Practically mitigated by making toggle-taps *keep* recording (so the user speaks after the overlay appears, absorbing the latency) rather than pre-warming the mic (which would keep the mic indicator on permanently).
- **Muting the system output cuts the start chime.** Muting immediately after `NSSound.play()` silences the still-playing chime. Defer the mute until the chime's `duration` elapses. Track "did we actually mute?" with a flag so a failed/short recording never restores a mute it didn't apply.
