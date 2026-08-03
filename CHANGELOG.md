# Changelog

Notes here are shown in the in-app update dialog. Each release is a `##` heading
matching the version number, followed by a bullet list of user-facing changes.

## 1.9.1

- System audio now mutes almost immediately when recording starts. It previously kept playing for about two seconds while waiting for the start chime's decay tail to finish.

## 1.7.1

- Fixed recording failing when your microphone and speakers are different devices (e.g. an audio interface for input and Bluetooth headphones for output).
- Added support for multi-channel audio interfaces such as the Focusrite Scarlett.
- Quick taps in Toggle mode are now reliably treated as taps instead of hold-to-talk.
- The start chime is no longer cut off, and system audio is always restored after a recording ends or fails.

## 1.7.0

- Parakeet (NVIDIA) transcription engine improvements and reliability fixes.
