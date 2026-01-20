import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            switch appState.recordingState {
            case .recording:
                RecordingView(
                    audioLevel: appState.audioLevel,
                    duration: appState.recordingDuration
                )
            case .transcribing:
                TranscribingView()
            case .error(let message):
                ErrorView(message: message)
            case .idle:
                EmptyView()
            }
        }
        .padding(16)
        .frame(width: 220, height: 90)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct RecordingView: View {
    let audioLevel: Float
    let duration: TimeInterval

    @State private var isPulsing = false
    @State private var ringScale: CGFloat = 1.0

    // Match the waveform colors
    private let accentColor = Color(red: 0.5, green: 0.5, blue: 1.0)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
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
                    withAnimation(
                        .easeOut(duration: 1.2)
                        .repeatForever(autoreverses: false)
                    ) {
                        ringScale = 1.8
                    }
                }

                Text("Recording")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                Text(formatDuration(duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Audio level waveform
            AudioWaveformView(level: audioLevel)
                .frame(height: 30)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

struct AudioWaveformView: View {
    let level: Float

    private let barCount = 24
    @State private var heights: [CGFloat] = Array(repeating: 0.15, count: 24)
    @State private var phase: Double = 0

    // Modern gradient colors
    private let gradientColors = [
        Color(red: 0.4, green: 0.6, blue: 1.0),  // Soft blue
        Color(red: 0.6, green: 0.4, blue: 1.0),  // Purple
        Color(red: 0.4, green: 0.8, blue: 0.9)   // Cyan
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: heights[index],
                    index: index,
                    totalBars: barCount,
                    gradientColors: gradientColors
                )
            }
        }
        .onChange(of: level) { _, newLevel in
            updateHeights(with: newLevel)
        }
        .onAppear {
            updateHeights(with: level)
        }
    }

    private func updateHeights(with level: Float) {
        let baseLevel = CGFloat(max(0.05, level))

        withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
            for i in 0..<barCount {
                // Create a smooth wave pattern emanating from center
                let centerDistance = abs(CGFloat(i) - CGFloat(barCount - 1) / 2) / CGFloat(barCount / 2)
                let wave = 1.0 - (centerDistance * 0.5)
                let randomFactor = CGFloat.random(in: 0.85...1.15)
                let newHeight = max(0.08, min(1.0, baseLevel * wave * randomFactor * 1.8))
                heights[i] = newHeight
            }
        }
    }
}

struct WaveformBar: View {
    let height: CGFloat
    let index: Int
    let totalBars: Int
    let gradientColors: [Color]

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 5, height: max(4, height * 30))
            .opacity(0.7 + (height * 0.3))
            .shadow(color: gradientColors[1].opacity(height * 0.5), radius: height * 4, y: 0)
    }
}

struct TranscribingView: View {
    @State private var isAnimating = false

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
        }
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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
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
