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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Pulsing recording indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("Recording")
                    .font(.headline)
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
        .onAppear {
            isPulsing = true
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

    private let barCount = 20
    @State private var heights: [CGFloat] = Array(repeating: 0.2, count: 20)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: heights[index] * 30)
            }
        }
        .onChange(of: level) { _, newLevel in
            updateHeights(with: newLevel)
        }
        .onAppear {
            updateHeights(with: level)
        }
    }

    private func barColor(for index: Int) -> Color {
        let height = heights[index]

        if height > 0.7 {
            return .red
        } else if height > 0.5 {
            return .orange
        } else {
            return .accentColor
        }
    }

    private func updateHeights(with level: Float) {
        let baseLevel = CGFloat(level)

        withAnimation(.easeOut(duration: 0.05)) {
            for i in 0..<barCount {
                // Create a wave pattern with some randomness
                let position = CGFloat(i) / CGFloat(barCount - 1)
                let wave = sin(position * .pi) * 0.3 + 0.2
                let randomFactor = CGFloat.random(in: 0.8...1.2)
                let newHeight = max(0.1, min(1.0, baseLevel * wave * randomFactor * 2))
                heights[i] = newHeight
            }
        }
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
