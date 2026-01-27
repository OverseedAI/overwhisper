import SwiftUI
import AVFoundation
import AppKit

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    let openAppSettings: () -> Void
    let finishOnboarding: () -> Void

    @State private var stepIndex: Int = 0
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityGranted: Bool = false

    private let totalSteps = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(stepTitle)
                .font(.system(size: 22, weight: .semibold))

            stepContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            HStack {
                if stepIndex > 0 {
                    Button("Back") {
                        stepIndex = max(stepIndex - 1, 0)
                    }
                }

                Spacer()

                if stepIndex < totalSteps - 1 {
                    Button("Continue") {
                        stepIndex = min(stepIndex + 1, totalSteps - 1)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish") {
                        finishOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .onAppear {
            refreshPermissions()
        }
    }

    private var stepTitle: String {
        switch stepIndex {
        case 0: return "Welcome to Overwhisper"
        case 1: return "Grant Permissions"
        case 2: return "Final Setup"
        default: return "Welcome"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch stepIndex {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text("Let’s get you ready to record and transcribe fast.")
                    .font(.title3)
                Text("We’ll check permissions and confirm your recording preferences.")
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Record from any microphone", systemImage: "mic.fill")
                    Label("Instant transcription with Whisper", systemImage: "waveform")
                    Label("Hotkey-driven workflow", systemImage: "keyboard")
                }
                .font(.subheadline)
            }
        case 1:
            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    title: "Microphone",
                    subtitle: "Required to capture audio",
                    status: microphoneStatusText,
                    statusColor: microphoneStatusColor,
                    actionTitle: microphoneActionTitle,
                    action: handleMicrophoneAction
                )

                PermissionRow(
                    title: "Accessibility",
                    subtitle: "Required to paste text into other apps",
                    status: accessibilityStatusText,
                    statusColor: accessibilityStatusColor,
                    actionTitle: accessibilityActionTitle,
                    action: handleAccessibilityAction
                )

                if microphoneStatus == .denied || !accessibilityGranted {
                    Text("If permissions are denied, use the action buttons to open System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose your preferred recording mode.")
                Picker("Recording Mode", selection: $appState.recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Divider().padding(.vertical, 8)

                Text("You can fine-tune models, hotkeys, and output behavior in Settings.")
                    .foregroundColor(.secondary)

                HStack {
                    Button("Open Settings") {
                        openAppSettings()
                    }
                    Spacer()
                    Button("Skip for now") {
                        finishOnboarding()
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private var microphoneStatusText: String {
        switch microphoneStatus {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private var microphoneStatusColor: Color {
        switch microphoneStatus {
        case .authorized: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }

    private var microphoneActionTitle: String {
        switch microphoneStatus {
        case .authorized: return "Granted"
        case .denied, .restricted: return "Open Settings"
        case .notDetermined: return "Request Access"
        @unknown default: return "Request"
        }
    }

    private func handleMicrophoneAction() {
        switch microphoneStatus {
        case .authorized:
            break
        case .denied, .restricted:
            openSystemSettings(for: "Microphone")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    refreshPermissions()
                }
            }
        @unknown default:
            break
        }
    }

    private var accessibilityStatusText: String {
        accessibilityGranted ? "Granted" : "Not granted"
    }

    private var accessibilityStatusColor: Color {
        accessibilityGranted ? .green : .red
    }

    private var accessibilityActionTitle: String {
        accessibilityGranted ? "Granted" : "Open Settings"
    }

    private func handleAccessibilityAction() {
        if accessibilityGranted {
            return
        }

        let requested = TextInserter.requestAccessibilityPermission()
        if !requested {
            openSystemSettings(for: "Accessibility")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = TextInserter.hasAccessibilityPermission()
    }

    private func openSystemSettings(for privacyPane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(privacyPane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let subtitle: String
    let status: String
    let statusColor: Color
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(status)
                .font(.caption)
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1))
                .cornerRadius(6)

            Button(actionTitle) {
                action()
            }
            .disabled(actionTitle == "Granted")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}

#Preview {
    let appState = AppState()
    return OnboardingView(openAppSettings: {}, finishOnboarding: {})
        .environmentObject(appState)
}
