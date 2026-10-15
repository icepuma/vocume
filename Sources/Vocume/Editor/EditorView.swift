import SwiftUI
import VocumeCore

/// The editor window: the screenshot laid on a lit table like a print, the tools and ink in the
/// toolbar beside Undo / Copy / Save, and the AI capsule floating at the bottom.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var settings = AISettings.shared
    @FocusState private var labelFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        print
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingBottomBar {
                if settings.isEnabled { Composer(model: model) }
            }
            .overlay(alignment: .top) { toastView.padding(.top, 14) }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: model.toast)
            .background { table.ignoresSafeArea() }
            .toolbar { toolbarContent }
            .navigationTitle(model.url.lastPathComponent)
            .navigationSubtitle(pixelSize)
            .frame(minWidth: 860, minHeight: 640)
    }

    // MARK: The table

    /// The light table, lit from beneath the print so the eye goes to the work.
    private var table: some View {
        // Dark: the system's graphite under-page grey. Light: a lighter table than the system's
        // mid-grey, so the window doesn't read as a dim slab under a light titlebar.
        (colorScheme == .dark ? Color(nsColor: .underPageBackgroundColor) : Color(red: 0.81, green: 0.81, blue: 0.82))
            .overlay {
                RadialGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.25), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: 620
                )
            }
    }

    /// The screenshot as a print resting on the table: a hairline edge and a soft lift shadow.
    private var print: some View {
        Image(nsImage: model.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay { GeometryReader { geometry in canvas(geometry.size) } }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.22), radius: 22, y: 10)
            .contextMenu { canvasMenu }
    }

    private var pixelSize: String {
        guard let rep = model.image.representations.first, rep.pixelsWide > 0 else { return "" }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh) px"
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: Binding(get: { model.tool }, set: { model.setTool($0) })) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Label(tool.title, systemImage: tool.icon).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Tools: V A R H X P T N")
        }
        ToolbarItem(placement: .principal) {
            InkButton(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(model.undoStack.isEmpty)
                .help("Undo  ⌘Z")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc", action: model.copyImage)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the annotated image  ⇧⌘C")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down").labelStyle(.titleOnly)
            }
            // Accent-filled on macOS 15. On macOS 26+ the bridged toolbar item stays a standard item:
            // neither this, `.glassProminent`, `.confirmationAction` nor AppKit's `style = .prominent`
            // changes how the system draws it there.
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s")
            .help("Save the annotated image  ⌘S")
        }
    }

    @ViewBuilder
    private var canvasMenu: some View {
        Button("Delete Mark", systemImage: "trash", action: model.deleteSelected)
            .disabled(model.selected == nil)
        Button("Clear All Marks", systemImage: "xmark.bin", action: model.clear)
            .disabled(model.marks.isEmpty)
        Divider()
        Button("Copy Image", systemImage: "doc.on.doc", action: model.copyImage)
        Button("Save…", systemImage: "square.and.arrow.down") { model.save() }
    }

    // MARK: Feedback

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .floatingGlass(in: Capsule())
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Canvas

    private func canvas(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                MarkRenderer.draw(
                    model.marks, in: context, size: canvasSize, selected: model.selected, editing: model.editing)
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { model.drag($0, in: size) }
                        .onEnded { model.end($0) }
                )
                .pointerStyle(model.tool == .select ? .default : .rectSelection)
            if let id = model.editing, let mark = model.marks.first(where: { $0.id == id }) {
                labelField(for: mark, in: size)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot, \(model.marks.count) \(model.marks.count == 1 ? "mark" : "marks")")
    }

    /// An inline text field over the mark's label pill, styled like the pill.
    private func labelField(for mark: Mark, in size: CGSize) -> some View {
        let pill = mark.labelRect(in: size)
        let fontSize = mark.fontSize(in: size)
        return TextField(
            "Text",
            text: Binding(
                get: { model.marks.first { $0.id == mark.id }?.label ?? "" },
                set: { text in model.update(mark.id) { $0.label = text } }
            )
        )
        .textFieldStyle(.plain)
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(Palette.ink(on: mark.color))
        .padding(.horizontal, fontSize * 0.5)
        .padding(.vertical, fontSize * 0.3)
        .background(Palette.color(named: mark.color), in: RoundedRectangle(cornerRadius: pill.height * 0.3))
        .fixedSize()
        .offset(x: pill.minX, y: pill.minY)
        .focused($labelFieldFocused)
        .onAppear { labelFieldFocused = true }
        .onSubmit { model.select(nil) }
        .id(mark.id)
    }
}
