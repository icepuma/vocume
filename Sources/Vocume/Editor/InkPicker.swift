import AppKit
import SwiftUI
import VocumeCore

/// The toolbar's ink control: shows the current colour and opens a popover with the inks and the
/// S/M/L sizes, so colour and size take one toolbar slot.
struct InkButton: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var presented = Presented()

    var body: some View {
        Button {
            presented.isOn.toggle()
        } label: {
            Label {
                Text("Ink")
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(Palette.color(named: model.colorName))
                    .overlay(Image(systemName: "circle").foregroundStyle(Color.primary.opacity(0.25)))
            }
        }
        .help("Colour and size")
        .popover(isPresented: $presented.isOn, arrowEdge: .bottom) {
            InkPicker(model: model) { presented.isOn = false }
        }
    }

    /// Popover state without `@State` (a macro unavailable with only the Command Line Tools).
    private final class Presented: ObservableObject {
        @Published var isOn = false
    }
}

/// The 8 inks, a row of custom colours (the two most recent, the screen eyedropper and the system
/// colour panel), and the 3 sizes.
struct InkPicker: View {
    @ObservedObject var model: EditorModel
    /// Closes the popover, so the eyedropper and colour panel aren't covered by it.
    let close: () -> Void
    @ObservedObject private var custom = CustomInks.shared
    @Environment(\.colorSchemeContrast) private var contrast

    static let sizes: [(name: String, size: Double, dot: CGFloat)] = [
        ("Small", 0.6, 6), ("Medium", 1.0, 10), ("Large", 1.6, 14),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(Palette.colors[(row * 4)..<(row * 4 + 4)], id: \.name) { entry in
                            swatch(entry.name, entry.color)
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<CustomInks.limit, id: \.self) { index in
                        if custom.recent.indices.contains(index) {
                            let hex = custom.recent[index]
                            swatch(hex, Palette.color(named: hex), label: "Custom colour \(hex)")
                        } else {
                            emptySlot
                        }
                    }
                    tool("eyedropper", help: "Pick a colour from the screen", action: pickFromScreen)
                    tool("paintpalette", help: "Show all colours", action: showColorPanel)
                }
            }
            Divider()
            HStack(spacing: 8) {
                ForEach(Self.sizes, id: \.name) { size in
                    sizeButton(size)
                }
            }
        }
        .padding(14)
    }

    private func swatch(_ name: String, _ color: Color, label: String? = nil) -> some View {
        let selected = model.colorName == name
        return Button {
            model.setColor(name)
        } label: {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.primary.opacity(hairlineOpacity(name)), lineWidth: 0.5))
                .frame(width: 22, height: 22)
                .padding(3)
                .overlay(Circle().stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label ?? name.capitalized)
        .accessibilityLabel(label ?? name.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Where a custom colour will appear once there is one.
    private var emptySlot: some View {
        Circle()
            .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
            .frame(width: 22, height: 22)
            .padding(3)
            .help("Colours you pick appear here")
            .accessibilityHidden(true)
    }

    /// A swatch-sized round button for picking a custom colour.
    private func tool(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .padding(3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The system's magnifier: click any pixel on screen, e.g. a background to redact over.
    private func pickFromScreen() {
        close()
        let model = model
        NSColorSampler().show { color in
            MainActor.assumeIsolated {
                guard let color, let hex = Palette.name(for: color) else { return }
                CustomInks.shared.remember(hex)
                model.setColor(hex)
            }
        }
    }

    private func showColorPanel() {
        close()
        ColorPanelLink.shared.open(for: model)
    }

    /// Black and white sit at the luminance extremes and vanish into one appearance without a
    /// firmer edge.
    private func hairlineOpacity(_ name: String) -> Double {
        if contrast == .increased { return 0.6 }
        return name == "black" || name == "white" ? 0.45 : 0.2
    }

    private func sizeButton(_ size: (name: String, size: Double, dot: CGFloat)) -> some View {
        let selected = model.size == size.size
        return Button {
            model.setSize(size.size)
        } label: {
            Circle()
                .fill(selected ? Color.white : Color.primary.opacity(0.6))
                .frame(width: size.dot, height: size.dot)
                .frame(width: 40, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(size.name) size")
        .accessibilityLabel("\(size.name) size")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The user's recent custom colours (`#RRGGBB`), newest first, shared by all editor windows.
@MainActor final class CustomInks: ObservableObject {
    static let shared = CustomInks()
    static let limit = 2
    private static let key = "customInks"

    @Published private(set) var recent = UserDefaults.standard.stringArray(forKey: key) ?? []

    /// Adds a colour in front; `replacingNewest` updates the front one instead (a colour still
    /// being adjusted in the colour panel).
    func remember(_ hex: String, replacingNewest: Bool = false) {
        var colors = recent
        if replacingNewest, !colors.isEmpty { colors.removeFirst() }
        colors.removeAll { $0 == hex }
        recent = Array(([hex] + colors).prefix(Self.limit))
        UserDefaults.standard.set(recent, forKey: Self.key)
    }
}

/// Connects the shared system colour panel to the editor that last opened it: its colour goes to
/// that editor's selected mark (or next mark) live, as one undo step and one recent colour.
@MainActor final class ColorPanelLink: NSObject {
    static let shared = ColorPanelLink()
    private weak var model: EditorModel?
    private var adjusting = false

    func open(for model: EditorModel) {
        self.model = model
        adjusting = false
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.showsAlpha = false
        panel.color = NSColor(Palette.color(named: model.colorName))
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let model, let hex = Palette.name(for: panel.color) else { return }
        CustomInks.shared.remember(hex, replacingNewest: adjusting)
        adjusting = true
        model.setColor(hex)
    }
}
