import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState
    var onCancel: () -> Void = {}

    // Smoothed voice level driving the halo: fast attack, slow decay,
    // so the light blooms on speech and settles during pauses.
    @State private var haloLevel: CGFloat = 0

    private var isCancellable: Bool {
        switch appState.recordingState {
        case .recording, .transcribing: return true
        case .idle, .error: return false
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            switch appState.recordingState {
            case .recording:
                RecordingView(
                    audioLevel: appState.audioLevel,
                    duration: appState.recordingDuration,
                    micStatus: appState.micInputStatus
                )
            case .transcribing:
                TranscribingView()
            case .error(let message):
                ErrorView(message: message)
            case .idle:
                EmptyView()
            }

            if isCancellable {
                CancelHintView(onCancel: onCancel)
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 25)
        .frame(width: OverlayMetrics.width, height: OverlayMetrics.height)
        .background(OverlaySurface(haloLevel: haloLevel))
        .onChange(of: appState.audioLevel) { _, newLevel in
            let boosted = CGFloat(sqrt(Double(min(1, max(0, newLevel)))))
            let target = max(boosted, haloLevel * 0.92)
            withAnimation(.easeOut(duration: 0.12)) {
                haloLevel = target
            }
        }
        .onChange(of: appState.recordingState) { _, state in
            if state != .recording {
                withAnimation(.easeOut(duration: 0.6)) {
                    haloLevel = 0
                }
            }
        }
    }
}

enum OverlayMetrics {
    static let width: CGFloat = 324
    static let height: CGFloat = 140
    static let surfaceInset = EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
    static let surfaceCornerRadius: CGFloat = 22
}

struct OverlaySurface: View {
    let haloLevel: CGFloat

    private var cornerRadius: CGFloat { OverlayMetrics.surfaceCornerRadius }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        ZStack {
            shape
                .fill(.black.opacity(0.22))
                .shadow(color: .black.opacity(0.30), radius: 18, y: 10)

            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.05, green: 0.06, blue: 0.07).opacity(0.88), location: 0),
                                .init(color: Color(red: 0.12, green: 0.13, blue: 0.14).opacity(0.84), location: 0.58),
                                .init(color: Color(red: 0.04, green: 0.05, blue: 0.055).opacity(0.90), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: 0.5)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.56, blue: 1.0).opacity(0),
                                Color(red: 0.55, green: 0.56, blue: 1.0).opacity(0.18 + haloLevel * 0.16),
                                Color(red: 0.35, green: 0.78, blue: 0.76).opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 86)
                    .blur(radius: 18)
                    .rotationEffect(.degrees(12))
                    .offset(x: 54 + haloLevel * 12)
            }
            .clipShape(shape)

            RoundedRectangle(cornerRadius: cornerRadius - 3, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
                .padding(5)

            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.26), location: 0),
                            .init(color: Color(red: 0.55, green: 0.58, blue: 1.0).opacity(0.16 + haloLevel * 0.16), location: 0.38),
                            .init(color: .black.opacity(0.14), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            shape
                .strokeBorder(.black.opacity(0.28), lineWidth: 1)
                .blendMode(.multiply)
        }
        .padding(OverlayMetrics.surfaceInset)
        .compositingGroup()
    }
}

struct CancelHintView: View {
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text("esc to cancel")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.72))

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
    }
}

struct RecordingView: View {
    let audioLevel: Float
    let duration: TimeInterval
    var micStatus: MicInputStatus = .ok

    @State private var isPulsing = false
    @State private var ringScale: CGFloat = 1.0

    // Match the waveform colors
    private let accentColor = Color(red: 0.52, green: 0.54, blue: 1.0)
    private let warningColor = Color(red: 1.0, green: 0.72, blue: 0.3)
    private let cautionColor = Color(red: 0.95, green: 0.85, blue: 0.4)

    private var headerTitle: String {
        switch micStatus {
        case .ok: return "RECORDING"
        case .low: return "LOW MIC LEVEL"
        case .silent: return "NO MIC INPUT"
        }
    }

    private var headerColor: Color {
        switch micStatus {
        case .ok: return .secondary
        case .low: return cautionColor
        case .silent: return warningColor
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                if micStatus == .silent {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(warningColor)
                        .frame(width: 18, height: 18)
                } else if micStatus == .low {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(cautionColor)
                        .frame(width: 18, height: 18)
                } else {
                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.16), lineWidth: 1)
                            .frame(width: 20, height: 20)
                            .scaleEffect(ringScale)
                            .opacity(max(0, 1.7 - ringScale))

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.92), accentColor],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 5
                                )
                            )
                            .frame(width: 8, height: 8)
                            .shadow(color: accentColor.opacity(0.55), radius: 6)
                    }
                    .frame(width: 24, height: 24)
                    .onAppear {
                        ringScale = 1.0
                        withAnimation(
                            .easeOut(duration: 1.4)
                            .repeatForever(autoreverses: false)
                        ) {
                            ringScale = 1.65
                        }
                    }
                }

                Text(headerTitle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .tracking(1.8)
                    .foregroundColor(headerColor)

                Spacer()

                Text(formatDuration(duration))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.82))
            }
            .animation(.easeInOut(duration: 0.25), value: micStatus)

            AudioWaveformView(level: audioLevel)
                .frame(height: 29)
                .opacity(micStatus == .silent ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.25), value: micStatus)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

/// Scrolling level history: new samples push in from the right and drift
/// left, so speech leaves a visible trail instead of dots wiggling in place.
struct AudioWaveformView: View {
    let level: Float

    private static let barCount = 42
    private let tick = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    @State private var history: [CGFloat] = Array(repeating: 0, count: barCount)

    private let gradientColors = [
        Color(red: 0.36, green: 0.52, blue: 0.98),
        Color(red: 0.62, green: 0.52, blue: 1.0),
        Color(red: 0.38, green: 0.76, blue: 0.74)
    ]

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0),
                            .white.opacity(0.055),
                            .white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 18)

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(history.indices, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: max(3, history[index] * 26))
                        .opacity(0.32 + history[index] * 0.68)
                        .shadow(
                            color: gradientColors[1].opacity(history[index] * 0.32),
                            radius: history[index] * 2
                        )
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .onReceive(tick) { _ in
            // sqrt boost keeps quiet-but-real speech visible (raw RMS for
            // normal speech sits low in the 0...1 range)
            let clamped = CGFloat(min(1, max(0, level)))
            let boosted = sqrt(clamped)
            let jitter = boosted > 0.05 ? CGFloat.random(in: -0.06...0.06) : 0

            withAnimation(.easeOut(duration: 0.08)) {
                history.removeFirst()
                history.append(min(1, max(0, boosted + jitter)))
            }
        }
    }
}

struct TranscribingView: View {
    @State private var isAnimating = false
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Spinning indicator
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))

                Text("Transcribing...")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Elapsed time so a long transcription doesn't look hung
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(Self.formatElapsed(context.date.timeIntervalSince(startedAt)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Animated dots
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: isAnimating
                        )
                }
                Spacer()
            }
        }
        .onAppear {
            isAnimating = true
            startedAt = Date()
        }
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)

                Text("Error")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()
            }

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Visual effect view for frosted glass background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var maskImage: NSImage? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.maskImage = maskImage
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.maskImage = maskImage
    }
}

#Preview {
    VStack(spacing: 20) {
        OverlayView(appState: {
            let state = AppState()
            state.recordingState = .recording
            state.audioLevel = 0.5
            state.recordingDuration = 5.3
            return state
        }())

        OverlayView(appState: {
            let state = AppState()
            state.recordingState = .recording
            state.micInputStatus = .silent
            state.recordingDuration = 4.0
            return state
        }())

        OverlayView(appState: {
            let state = AppState()
            state.recordingState = .transcribing
            return state
        }())

        OverlayView(appState: {
            let state = AppState()
            state.recordingState = .error("Model failed to load")
            return state
        }())
    }
    .padding()
    .background(Color.gray)
}
