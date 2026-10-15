import SwiftUI
import VocumeCore

/// The floating AI bar at the bottom of the table: one 44 pt capsule with three slots — model menu,
/// prompt, send — each round control inset 6 pt so it sits concentric in the capsule.
///
/// While a request runs the same slots show the progress instead: the rainbow status in the middle
/// and a stop button where send was (Esc also stops). Nothing moves and nothing new can be typed.
struct Composer: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var settings = AISettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static let height: CGFloat = 44
    static let inset: CGFloat = 6
    static let control: CGFloat = height - inset * 2

    var body: some View {
        VStack(spacing: 8) {
            if !model.error.isEmpty && !model.isBusy {
                errorNote.transition(.opacity)
            }
            capsule
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.isBusy)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.error)
    }

    private var capsule: some View {
        HStack(spacing: 4) {
            if model.isBusy {
                busyContent
            } else if let backend = model.activeBackend {
                idleContent(backend)
            } else {
                setupContent
            }
        }
        .padding(Self.inset)
        .frame(height: Self.height)
        // While busy the bar turns into a dark terminal strip in both appearances: Claude Code's
        // pastel rainbow needs a dark ground to stay legible.
        .background {
            if model.isBusy {
                Capsule().fill(Color(white: 0.1).opacity(0.94))
            }
        }
        .environment(\.colorScheme, model.isBusy ? .dark : colorScheme)
        .floatingGlass(in: Capsule())
        .overlay {
            if model.isBusy {
                ProgressRule(since: model.busySince)
            }
        }
    }

    @ViewBuilder
    private func idleContent(_ backend: AIBackend) -> some View {
        Menu {
            Picker("Model", selection: Binding(get: { backend }, set: { model.backend = $0 })) {
                ForEach(settings.usable) { option in
                    Text(option == .ollama ? "Ollama · \(settings.ollamaModel)" : option.displayName).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("AI Settings…", action: Windows.shared.showSettings)
        } label: {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.control, height: Self.control)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("AI: \(backend.displayName)")
        .accessibilityLabel("AI provider, \(backend.displayName)")

        TextField("Ask \(backend.displayName) to mark up this screenshot", text: $model.prompt)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 4)
            .onSubmit(model.askAI)

        Button(action: model.askAI) {
            Label("Annotate", systemImage: "arrow.up").labelStyle(.iconOnly)
        }
        .buttonStyle(RoundActionStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .help("Annotate  ↩")
    }

    /// No usable provider yet: say why in one line and offer Settings.
    @ViewBuilder
    private var setupContent: some View {
        let checking = AIBackend.allCases.contains { settings.status[$0] == nil || settings.status[$0] == .checking }
        Image(systemName: "sparkle")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.control, height: Self.control)
        Text(checking ? "Looking for AI providers…" : "No AI provider is set up")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        if !checking {
            Button("Settings…", action: Windows.shared.showSettings)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.trailing, 2)
        }
    }

    @ViewBuilder
    private var busyContent: some View {
        AIProgressLine(stage: model.stage, since: model.busySince)
            .padding(.leading, 12)
        Button(action: model.cancelAI) {
            Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly)
        }
        .buttonStyle(RoundActionStyle())
        .help("Stop  Esc")
    }

    private var errorNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(model.error)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(model.error)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark") { model.error = "" }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .floatingGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Claude Code's keyword rainbow: its theme keys `rainbow_red`…`rainbow_violet` and the lighter
/// `*_shimmer` variants (identical in its light and dark themes).
enum Rainbow {
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

/// The request's status, animated the way Claude Code animates its ultra* keywords: each character
/// takes the next rainbow colour, and a 3-character glimmer band of the shimmer colours sweeps
/// left→right at 1 char / 50 ms (from 10 chars before the text to 10 after), stepped on Claude
/// Code's 64 ms animation tick. With Reduce Motion the band is parked off-screen, as Claude Code does.
struct AIProgressLine: View {
    let stage: String
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(since) * 1000) / 64 * 64
            let chars = Array(stage + "…")
            let glimmer = reduceMotion ? -100 : -10 + (elapsed / 50) % (chars.count + 20)
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Rainbow.base[(reduceMotion ? 0 : elapsed / 150) % 7])
                chars.enumerated().reduce(Text("")) { line, char in
                    let palette = abs(char.offset - glimmer) <= 1 ? Rainbow.shimmer : Rainbow.base
                    return Text("\(line)\(Text(String(char.element)).foregroundStyle(palette[char.offset % 7]))")
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%.1fs", timeline.date.timeIntervalSince(since)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage)
    }
}

/// The capsule's border while a request runs: terminal-cell-sized segments in scrolling rainbow
/// colours (segment `i` gets colour `i + t/150`), Claude Code's rainbow rule.
private struct ProgressRule: View {
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : Int(timeline.date.timeIntervalSince(since) * 1000) / 150
            Canvas { context, size in
                let path = Capsule().path(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75))
                let segments = max(Int((size.width + size.height) * 2 / 9), 7)  // ~9 pt each, like a "─" cell
                for segment in 0..<segments {
                    context.stroke(
                        // Each segment overlaps the next slightly, so the rule reads as one line.
                        path.trimmedPath(
                            from: Double(segment) / Double(segments),
                            to: min(Double(segment) + 1.25, Double(segments)) / Double(segments)
                        ),
                        with: .color(Rainbow.base[(segment + phase) % 7]),
                        lineWidth: 1.5
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The bar's round action (send, stop): a solid accent circle with a white glyph, sized to sit
/// concentric in the capsule. A solid fill, not glass, because the capsule is already the one glass
/// layer; drawn by hand because a circle-shaped `.borderedProminent` button loses its accent fill
/// on macOS.
private struct RoundActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Composer.control, height: Composer.control)
            .background(Circle().fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4)))
            .brightness(configuration.isPressed ? -0.1 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}
