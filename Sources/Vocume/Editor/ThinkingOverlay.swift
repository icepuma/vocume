import SwiftUI

/// Claude Code's keyword rainbow: its theme keys `rainbow_red`…`rainbow_violet` and the lighter
/// `*_shimmer` variants (identical in its light and dark themes).
private enum Rainbow {
    static let base = colors([
        (235, 95, 87), (245, 139, 87), (250, 195, 95), (145, 200, 130), (130, 170, 220),
        (155, 130, 200), (200, 130, 180),
    ])
    static let shimmer = colors([
        (250, 155, 147), (255, 185, 137), (255, 225, 155), (185, 230, 180), (180, 205, 240),
        (195, 180, 230), (230, 180, 210),
    ])

    private static func colors(_ rgb: [(Double, Double, Double)]) -> [Color] {
        rgb.map { Color(red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }
    }
}

/// Covers the prompt field while the AI works, animated the way Claude Code animates its ultra* keywords.
///
/// Each character takes the next rainbow colour, and a 3-character glimmer band of the shimmer colours
/// sweeps left→right at 1 char / 50 ms (from 10 chars before the text to 10 after), stepped on Claude
/// Code's 64 ms animation tick. The border is its scrolling rainbow rule. The overlay swallows clicks, so
/// nothing new can be entered while a request runs.
struct ThinkingOverlay: View {
    let stage: String
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(since) * 1000) / 64 * 64
            let chars = Array(stage + "…")
            // With reduced motion the band is parked off-screen, as Claude Code does.
            let glimmer = reduceMotion ? -100 : -10 + (elapsed / 50) % (chars.count + 20)
            let phase = reduceMotion ? 0 : elapsed / 150
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack(spacing: 8) {
                Text("✻").foregroundStyle(Rainbow.base[phase % 7])
                chars.enumerated().reduce(Text("")) { line, char in
                    let palette = abs(char.offset - glimmer) <= 1 ? Rainbow.shimmer : Rainbow.base
                    return Text("\(line)\(Text(String(char.element)).foregroundStyle(palette[char.offset % 7]))")
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%.1fs", timeline.date.timeIntervalSince(since))).foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(.background))
            .overlay(RainbowRule(phase: phase))
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stage)
        }
    }
}

/// The rounded border, drawn as a row of terminal-cell-sized segments in scrolling rainbow colours
/// (segment `i` gets colour `i + phase`).
private struct RainbowRule: View {
    let phase: Int

    var body: some View {
        Canvas { context, size in
            let path = Path(
                roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1),
                cornerRadius: 8,
                style: .continuous
            )
            let segments = max(Int((size.width + size.height) * 2 / 9), 7)  // ~9 pt each, like a "─" cell
            for segment in 0..<segments {
                context.stroke(
                    path.trimmedPath(
                        from: Double(segment) / Double(segments),
                        to: Double(segment + 1) / Double(segments)
                    ),
                    with: .color(Rainbow.base[(segment + phase) % 7]),
                    lineWidth: 2
                )
            }
        }
        .allowsHitTesting(false)
    }
}
