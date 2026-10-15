import SwiftUI
import VocumeCore

/// The editor window: tool bar, the screenshot with its marks, and the AI prompt bar.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    @FocusState private var labelFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            Divider()
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: model.image).resizable().aspectRatio(contentMode: .fit)
                    .overlay { GeometryReader { geometry in canvas(geometry.size) } }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    .padding(28)
            }
            .overlay(alignment: .top) { toastView }
            .animation(.spring(duration: 0.3), value: model.toast)
            Divider()
            aiBar
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    @ViewBuilder private var toastView: some View {
        if let toast = model.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var toolBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 2) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Button {
                        model.setTool(tool)
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 28)
                            .foregroundStyle(model.tool == tool ? Color.accentColor : .primary)
                            .background(
                                model.tool == tool ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.rawValue.capitalized)  \(tool.key.uppercased())")
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 4) {
                ForEach(Palette.colors, id: \.name) { entry in
                    Circle().fill(entry.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                model.colorName == entry.name ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .contentShape(Circle())
                        .onTapGesture { model.setColor(entry.name) }
                        .help(entry.name.capitalized)
                }
            }

            Picker("Size", selection: Binding(get: { model.size }, set: { model.setSize($0) })) {
                Text("S").tag(0.6)
                Text("M").tag(1.0)
                Text("L").tag(1.6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            .help("Size")

            Spacer()

            HStack(spacing: 12) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .help("Undo  ⌘Z")
                    .disabled(model.undoStack.isEmpty)
                Button("Delete", systemImage: "trash") { model.deleteSelected() }
                    .help("Delete selected  ⌫")
                    .disabled(model.selected == nil)
                Button("Clear All", systemImage: "xmark.bin") { model.clear() }
                    .help("Clear all")
                    .disabled(model.marks.isEmpty)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)

            HStack(spacing: 8) {
                Button("Copy", systemImage: "doc.on.doc") { model.copyImage() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("Copy annotated image  ⇧⌘C")
                Button("Save", systemImage: "square.and.arrow.down") { model.save() }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .help("Save annotated image  ⌘S")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var aiBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.purple).imageScale(.large)
                Picker("Model", selection: $model.backend) {
                    ForEach(AIBackend.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(model.isBusy)
                HStack(spacing: 10) {
                    TextField("Ask AI to annotate, e.g. “point out UI bugs”", text: $model.prompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(model.askAI)
                    Button("Annotate", action: model.askAI)
                }
                .disabled(model.isBusy)
                .overlay {
                    if model.isBusy {
                        ThinkingOverlay(stage: model.stage, since: model.busySince)
                            .padding(-2)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.spring(duration: 0.4), value: model.isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

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
