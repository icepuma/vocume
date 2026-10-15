import SwiftUI
import VocumeCore

/// The toolbar's ink control: shows the current colour and opens a popover with the 8 inks and
/// the S/M/L sizes, so colour and size take one toolbar slot instead of eleven.
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
            InkPicker(model: model)
        }
    }

    /// Popover state without `@State` (a macro unavailable with only the Command Line Tools).
    private final class Presented: ObservableObject {
        @Published var isOn = false
    }
}

/// The 8 inks and 3 sizes.
struct InkPicker: View {
    @ObservedObject var model: EditorModel
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

    private func swatch(_ name: String, _ color: Color) -> some View {
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
        .help(name.capitalized)
        .accessibilityLabel(name.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
