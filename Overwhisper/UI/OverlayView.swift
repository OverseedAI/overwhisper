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
        .padding(.horizontal, 84)
        .padding(.vertical, 56)
        .frame(width: OverlayMetrics.width, height: OverlayMetrics.height)
        .background(
            ZStack {
                // Frosted glass pooled in an ellipse — no straight edges.
                // maskImage feathers the behind-window blur; the elliptical
                // SwiftUI mask below feathers the in-process layers the same.
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    maskImage: OverlayMetrics.featheredMask
                )

                // Dark heart of the pool — anchors contrast so the halo
                // reads as glowing light, not pale fog over bright desktops
                EllipticalGradient(
                    stops: [
                        .init(color: .black.opacity(0.68), location: 0),
                        .init(color: .black.opacity(0.58), location: 0.65),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center
                )

                // Aurora glows that brighten with the voice
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .frame(width: 180, height: 180)
                    .blur(radius: 46)
                    .opacity(0.22 + haloLevel * 0.30)
                    .offset(x: -70, y: -18)

                Circle()
                    .fill(Color(red: 0.4, green: 0.8, blue: 0.9))
                    .frame(width: 170, height: 170)
                    .blur(radius: 48)
                    .opacity(0.17 + haloLevel * 0.24)
                    .offset(x: 78, y: 22)
            }
            .mask(
                EllipticalGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.70),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center
                )
            )
            // The whole pool of light swells with speech
            .scaleEffect(0.94 + haloLevel * 0.10)
        )
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
    static let width: CGFloat = 384
    static let height: CGFloat = 200

    /// Alpha mask for the blur backdrop: an elliptical pool of light —
    /// opaque in the middle, feathering radially to nothing, so the glass
    /// has no edges at all.
    static let featheredMask: NSImage = makeEllipticalMask(
        size: NSSize(width: width, height: height)
    )

    private static func makeEllipticalMask(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let colors = [
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0).cgColor
            ] as CFArray

            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.70, 1]
            ) else { return false }

            // Unit-circle gradient stretched to the view's aspect ratio
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: rect.width / 2, y: rect.height / 2)
            ctx.drawRadialGradient(
                gradient,
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: 1,
                options: []
            )

            return true
        }
    }
}

struct CancelHintView: View {
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text("esc to cancel")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))

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
    private let accentColor = Color(red: 0.5, green: 0.5, blue: 1.0)
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
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
                    // Modern pulsing recording indicator with ring
                    ZStack {
                        // Outer pulsing ring
                        Circle()
                            .stroke(accentColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .scaleEffect(ringScale)
                            .opacity(2.0 - ringScale)

                        // Inner solid circle
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: accentColor.opacity(0.6), radius: 4)
                    }
                    .onAppear {
                        ringScale = 1.0
                        withAnimation(
                            .easeOut(duration: 1.2)
                            .repeatForever(autoreverses: false)
                        ) {
                            ringScale = 1.8
                        }
                    }
                }

                Text(headerTitle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .tracking(1.8)
                    .foregroundColor(headerColor)

                Spacer()

                Text(formatDuration(duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
            }
            .animation(.easeInOut(duration: 0.25), value: micStatus)

            // Audio level waveform
            AudioWaveformView(level: audioLevel)
                .frame(height: 34)
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

    private static let barCount = 36
    private let tick = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    @State private var history: [CGFloat] = Array(repeating: 0, count: barCount)

    private let gradientColors = [
        Color(red: 0.4, green: 0.6, blue: 1.0),  // Soft blue
        Color(red: 0.6, green: 0.4, blue: 1.0),  // Purple
        Color(red: 0.4, green: 0.8, blue: 0.9)   // Cyan
    ]

    var body: some View {
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
                    .frame(width: 3, height: max(3, history[index] * 34))
                    .opacity(0.55 + history[index] * 0.45)
                    .shadow(
                        color: gradientColors[1].opacity(history[index] * 0.6),
                        radius: history[index] * 3
                    )
            }
        }
        .frame(maxWidth: .infinity)
        // Fade out the oldest samples on the left
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.25),
                    .init(color: .black, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
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
