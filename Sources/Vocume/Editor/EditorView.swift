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
        GeometryReader { geometry in workspace(geometry.size) }
            .floatingBottomBar {
                if settings.isEnabled { Composer(model: model) }
            }
            .overlay(alignment: .top) { toastView.padding(.top, 14) }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: model.toast)
            .background { table.ignoresSafeArea() }
            .toolbar { toolbarContent }
            .navigationTitle(model.url.lastPathComponent)
            .navigationSubtitle(pixelSize)
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    /// Wide enough that every toolbar item fits, even with a long capture name (the title
    /// shortens first). Narrower, Copy and Save would move into the » overflow menu.
    static let minimumSize = CGSize(width: 1000, height: 640)

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

    /// The print fitted to the window, or at a set zoom in a scroll view that stays centred as it
    /// grows. Pinching zooms either way.
    private func workspace(_ size: CGSize) -> some View {
        let viewport = CGSize(width: max(size.width - 56, 1), height: max(size.height - 56, 1))
        return Group {
            if let zoomed = model.zoomedSize {
                ScrollView([.horizontal, .vertical]) {
                    print(zoomed)
                        .padding(28)
                        .frame(minWidth: size.width, minHeight: size.height)
                }
                .defaultScrollAnchor(.center)
                .defaultScrollAnchor(.center, for: .sizeChanges)
            } else {
                print(nil)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { model.pinch($0.magnification) }
                .onEnded { _ in model.endPinch() }
        )
        .onAppear { model.viewport = viewport }
        .onChange(of: viewport) { model.viewport = viewport }
    }

    /// The screenshot as a print resting on the table: a hairline edge and a soft lift shadow.
    /// `size` fixes it at a zoom; `nil` fits it to the space. Only the cropped part shows: the
    /// whole image and its marks are laid out full size and shifted, so marks keep whole-image
    /// coordinates.
    private func print(_ size: CGSize?) -> some View {
        let crop = model.visibleCrop
        let visible = model.visiblePixelSize
        return Color.clear
            .aspectRatio(visible.width / max(visible.height, 1), contentMode: .fit)
            .frame(width: size?.width, height: size?.height)
            .overlay {
                GeometryReader { geometry in
                    let full = CGSize(
                        width: geometry.size.width / crop.width, height: geometry.size.height / crop.height)
                    let offset = CGPoint(x: crop.minX * full.width, y: crop.minY * full.height)
                    // Drawing at the bottom, then mouse input, then the label field being edited.
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: model.image).resizable().frame(width: full.width, height: full.height)
                        canvas(full)
                    }
                    .frame(width: full.width, height: full.height, alignment: .topLeading)
                    .offset(x: -offset.x, y: -offset.y)
                    .allowsHitTesting(false)
                    gestures(full: full, offset: offset)
                    if let id = model.editing, let mark = model.marks.first(where: { $0.id == id }) {
                        labelField(for: mark, in: full)
                            .frame(width: full.width, height: full.height, alignment: .topLeading)
                            .offset(x: -offset.x, y: -offset.y)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.22), radius: 22, y: 10)
            .contextMenu { canvasMenu }
    }

    /// The size an export will have: the cropped part, also while the Crop tool shows everything.
    private var pixelSize: String {
        let crop = model.crop ?? EditorModel.wholeImage
        let size = CGSize(width: model.pixelSize.width * crop.width, height: model.pixelSize.height * crop.height)
        guard size.width > 0 else { return "" }
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
            + (model.crop == nil ? "" : " (cropped)")
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
            .help("Tools: V A L R O H X P T N C")
        }
        ToolbarItem(placement: .principal) {
            InkButton(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Zoom In", action: model.zoomIn)
                Button("Zoom Out", action: model.zoomOut)
                Button("Actual Size") { model.setZoom(1) }
                Button("Zoom to Fit", action: model.zoomToFit)
                Divider()
                ForEach([0.5, 1, 2, 4], id: \.self) { level in
                    Button("\(Int(level * 100))%") { model.setZoom(level) }
                }
            } label: {
                Text("\(Int((model.effectiveZoom * 100).rounded()))%").monospacedDigit()
            }
            .fixedSize()
            .help("Zoom  ⌘+  ⌘−  ⌘0 actual size  ⌘9 fit")
            .accessibilityLabel("Zoom, \(Int((model.effectiveZoom * 100).rounded())) percent")
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
            // Not a button: a button takes the mouse-down, so the drag would never start.
            Image(systemName: "hand.draw")
                .font(.system(size: 15))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onDrag { model.dragItem() }
                .onTapGesture { model.flash("Drag this into another app") }
                .help("Drag the annotated image into another app")
                .accessibilityLabel("Drag the annotated image into another app")
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
        // Common actions first, destructive ones last.
        Button("Copy Image", systemImage: "doc.on.doc", action: model.copyImage)
        Button("Save…", systemImage: "square.and.arrow.down") { model.save() }
        Divider()
        Button("Reset Crop", systemImage: "crop", action: model.resetCrop)
            .disabled(model.crop == nil)
        Divider()
        Button("Delete Mark", systemImage: "trash", action: model.deleteSelected)
            .disabled(model.selected == nil)
        Button("Clear All Marks", systemImage: "xmark.bin", action: model.clear)
            .disabled(model.marks.isEmpty)
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

    /// The marks (and the crop frame while cropping), drawn over the whole image at `size`.
    private func canvas(_ size: CGSize) -> some View {
        Canvas { context, canvasSize in
            MarkRenderer.draw(
                model.marks, in: context, size: canvasSize, selected: model.selected, editing: model.editing)
            if model.tool == .crop, let crop = model.crop {
                MarkRenderer.drawCrop(crop, in: context, size: canvasSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot, \(model.marks.count) \(model.marks.count == 1 ? "mark" : "marks")")
    }

    /// Mouse input on the visible part of the print, handed on in whole-image coordinates.
    private func gestures(full: CGSize, offset: CGPoint) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { model.drag($0, in: full, offset: offset) }
                    .onEnded { model.end($0) }
            )
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    model.hover(at: location, in: full, offset: offset)
                } else {
                    model.hover(at: nil, in: full)
                }
            }
            .pointerStyle(pointerStyle)
    }

    /// Resize arrows over a box's handles, a hand over an arrow's ends, a crosshair while drawing.
    private var pointerStyle: PointerStyle {
        guard let handle = model.hoveredHandle else { return model.tool == .select ? .default : .rectSelection }
        let positions: [UnitPoint: FrameResizePosition] = [
            .topLeading: .topLeading, .top: .top, .topTrailing: .topTrailing, .trailing: .trailing,
            .bottomTrailing: .bottomTrailing, .bottom: .bottom, .bottomLeading: .bottomLeading, .leading: .leading,
        ]
        let kind = model.marks.first { $0.id == model.selected }?.kind
        guard kind != .arrow, kind != .line, let position = positions[handle] else { return .grabIdle }
        return .frameResize(position: position)
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
