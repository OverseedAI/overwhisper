import AppKit

/// Generates the Overwhisper menubar icon - a simplified waveform with 7 bars
enum MenuBarIcon {

    /// Bar heights for idle state - asymmetric pattern like real audio
    private static let idleHeights: [CGFloat] = [0.35, 0.6, 0.45, 1.0, 0.5, 0.75, 0.4]

    /// Animation frames for recording - subtle variations from idle
    static let recordingFrames: [[CGFloat]] = [
        [0.35, 0.6, 0.45, 1.0, 0.5, 0.75, 0.4],   // base
        [0.4, 0.55, 0.5, 0.95, 0.55, 0.7, 0.45],
        [0.38, 0.65, 0.4, 1.0, 0.45, 0.8, 0.38],
        [0.42, 0.58, 0.48, 0.92, 0.52, 0.72, 0.42],
        [0.33, 0.62, 0.42, 0.98, 0.48, 0.78, 0.36],
        [0.37, 0.57, 0.47, 0.96, 0.53, 0.73, 0.43],
    ]

    /// Number of loading animation frames (dots: 1, 2, 3)
    static let loadingFrameCount = 3

    /// Draws bars centered vertically in the rect
    private static func drawBarsCentered(in rect: NSRect, heights: [CGFloat], barWidth: CGFloat = 2, spacing: CGFloat = 1.5, maxHeight: CGFloat? = nil) {
        let barCount = heights.count
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (rect.width - totalWidth) / 2
        let height = maxHeight ?? rect.height * 0.85
        let centerY = rect.height / 2

        for (index, heightPercent) in heights.enumerated() {
            let barHeight = max(height * heightPercent, barWidth)
            let x = startX + CGFloat(index) * (barWidth + spacing)
            let y = centerY - barHeight / 2

            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSColor.black.setFill()
            path.fill()
        }
    }

    /// Draws bars with a fixed baseline (for states with indicators below)
    private static func drawBarsWithBaseline(in rect: NSRect, heights: [CGFloat], barWidth: CGFloat = 2, spacing: CGFloat = 1.5, maxHeight: CGFloat, baseY: CGFloat) {
        let barCount = heights.count
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (rect.width - totalWidth) / 2

        for (index, heightPercent) in heights.enumerated() {
            let barHeight = max(maxHeight * heightPercent, barWidth)
            let x = startX + CGFloat(index) * (barWidth + spacing)

            let barRect = NSRect(x: x, y: baseY, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSColor.black.setFill()
            path.fill()
        }
    }

    /// Creates the menubar icon image - idle state
    static func create(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawBarsCentered(in: rect, heights: idleHeights)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates a recording animation frame
    static func createRecordingFrame(_ frameIndex: Int, size: CGFloat = 18) -> NSImage {
        let heights = recordingFrames[frameIndex % recordingFrames.count]
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawBarsCentered(in: rect, heights: heights)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates a loading animation frame with dots (1, 2, or 3 dots)
    static func createLoadingFrame(_ frameIndex: Int, size: CGFloat = 18) -> NSImage {
        let dotCount = (frameIndex % loadingFrameCount) + 1  // 1, 2, or 3 dots
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Draw waveform in upper portion
            drawBarsWithBaseline(in: rect, heights: idleHeights, maxHeight: rect.height * 0.55, baseY: 7)

            // Draw dots at bottom
            let dotSize: CGFloat = 2.5
            let dotSpacing: CGFloat = 2.5
            let maxDotsWidth = 3 * dotSize + 2 * dotSpacing
            let dotsStartX = (rect.width - maxDotsWidth) / 2

            for i in 0..<dotCount {
                let dotRect = NSRect(
                    x: dotsStartX + CGFloat(i) * (dotSize + dotSpacing),
                    y: 1,
                    width: dotSize,
                    height: dotSize
                )
                let dotPath = NSBezierPath(ovalIn: dotRect)
                NSColor.black.setFill()
                dotPath.fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates a transcribing state icon with ellipsis below
    static func createTranscribing(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawBarsWithBaseline(in: rect, heights: idleHeights, maxHeight: rect.height * 0.55, baseY: 7)

            // Three dots at bottom
            let dotSize: CGFloat = 2.5
            let dotSpacing: CGFloat = 2.5
            let dotsWidth = 3 * dotSize + 2 * dotSpacing
            let dotsStartX = (rect.width - dotsWidth) / 2

            for i in 0..<3 {
                let dotRect = NSRect(
                    x: dotsStartX + CGFloat(i) * (dotSize + dotSpacing),
                    y: 1,
                    width: dotSize,
                    height: dotSize
                )
                let dotPath = NSBezierPath(ovalIn: dotRect)
                NSColor.black.setFill()
                dotPath.fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates an error state icon with warning indicator
    static func createError(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawBarsWithBaseline(in: rect, heights: idleHeights, maxHeight: rect.height * 0.5, baseY: 8)

            // Exclamation mark at bottom center
            let exclamationWidth: CGFloat = 2
            let exclamationHeight: CGFloat = 4
            let exclamationRect = NSRect(
                x: (rect.width - exclamationWidth) / 2,
                y: 2.5,
                width: exclamationWidth,
                height: exclamationHeight
            )
            let exclamationPath = NSBezierPath(roundedRect: exclamationRect, xRadius: exclamationWidth / 2, yRadius: exclamationWidth / 2)
            NSColor.black.setFill()
            exclamationPath.fill()

            // Dot below exclamation
            let dotSize: CGFloat = 2
            let dotRect = NSRect(
                x: (rect.width - dotSize) / 2,
                y: 0,
                width: dotSize,
                height: dotSize
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)
            dotPath.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
