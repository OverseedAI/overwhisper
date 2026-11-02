# Changelog

Notes here are shown in the in-app update dialog. Each release is a `##` heading
matching the version number, followed by a bullet list of user-facing changes.

## 1.10.0

- Choose Small, Medium, or Large transcription models with clear speed and accuracy guidance. Exact model variants remain available under Advanced.
- Model choices now follow your language and translation settings. Switching languages never starts an unexpected download, and existing model selections are preserved.
- Expanded the language picker, including Hindi, Bengali, Urdu, and more.
- Retry failed transcriptions or transcribe saved recordings again from History.
- Choose how long to keep saved recordings, with automatic cleanup by age or recording count.
- Fixed Escape cancellation so the key does not also reach the app you are dictating into, and cancelled transcriptions cannot insert late results.
- Improved model switching, download status, and recognition of previously downloaded models.

## 1.9.3

- Fixed "Mute system audio while recording" with AirPods and other Bluetooth headsets. Opening the microphone switches the headset to a different audio profile with its own mute state, so music could keep playing during the recording and the headphones could stay muted afterwards. The mute now follows the profile switch in both directions.

## 1.9.2

- System audio now mutes within about a third of a second of starting a recording. The mute no longer waits for the microphone to spin up, and the start chime holds it off for at most 0.3s.

## 1.9.1

- System audio now mutes almost immediately when recording starts. It previously kept playing for about two seconds while waiting for the start chime's decay tail to finish.

## 1.7.1

- Fixed recording failing when your microphone and speakers are different devices (e.g. an audio interface for input and Bluetooth headphones for output).
- Added support for multi-channel audio interfaces such as the Focusrite Scarlett.
- Quick taps in Toggle mode are now reliably treated as taps instead of hold-to-talk.
- The start chime is no longer cut off, and system audio is always restored after a recording ends or fails.

## 1.7.0

- Parakeet (NVIDIA) transcription engine improvements and reliability fixes.
