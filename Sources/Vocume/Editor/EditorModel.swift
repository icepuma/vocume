import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import VocumeCore

/// State and actions for one editor window.
///
/// `ObservableObject` rather than `@Observable`/`@State`: those are macros, and the Command Line
/// Tools ship without the SwiftUI macro plugin, so the app must build without them.
@MainActor final class EditorModel: ObservableObject {
    /// The image as a plain file, for OCR and the AI.
    let url: URL
    let image: NSImage
    private let imageData: Data
    /// The `.vocume` document the editor saves to, by itself: closing never asks.
    let documentURL: URL
    weak var window: NSWindow?

    @Published var marks: [Mark] = [] {
        didSet {
            guard marks != oldValue else { return }
            edited()
            if !restoring { redoStack = [] }  // a new edit ends the redo history
        }
    }
    /// The part of the image kept, in fractions of it; `nil` keeps everything. Marks stay in
    /// whole-image coordinates, so a crop never moves them and can be changed or undone any time.
    @Published private(set) var crop: CGRect? {
        didSet {
            guard crop != oldValue else { return }
            edited()
            if !restoring { redoStack = [] }
        }
    }
    typealias Snapshot = VocumeDocument.State
    private var state: Snapshot {
        get { Snapshot(marks: marks, crop: crop) }
        set {
            marks = newValue.marks
            crop = newValue.crop
        }
    }
    /// Undo or redo is putting back an earlier state.
    private var restoring = false
    /// Edits so far, and how many the document file has.
    private var edits = 0
    private var savedEdits = 0
    @Published private(set) var undoStack: [Snapshot] = []
    @Published private(set) var redoStack: [Snapshot] = []
    @Published private(set) var tool = Tool.arrow
    @Published private(set) var colorName = Palette.defaultName
    @Published private(set) var size = 1.0
    @Published private(set) var selected: UUID?
    @Published var editing: UUID?
    /// Screen pixels per image pixel (1 = Actual Size); `nil` fits the image to the window.
    @Published private(set) var zoom: Double?
    /// The space the print can take, in points (set by the view); fit and the zoom steps use it.
    @Published var viewport = CGSize.zero
    private var pinchStart: Double?
    static let zoomSteps = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    /// The selected mark's handle under the pointer, for the resize cursor.
    @Published private(set) var hoveredHandle: UnitPoint?

    @Published var prompt = ""
    /// The provider the user picked in the AI bar; see `activeBackend` for the one actually used.
    @Published var backend = AIBackend.claude
    let settings = AISettings.shared
    @Published private(set) var isBusy = false
    /// What the AI step is doing, shown in the overlay.
    @Published private(set) var stage = ""
    @Published private(set) var busySince = Date()
    @Published var error = ""
    @Published private(set) var toast: String?

    // Drag state.
    private var active: UUID?
    private var dragStart: Mark?
    /// The handle being dragged when the drag reshapes the selected mark instead of moving it.
    private var resizing: UnitPoint?
    /// The last coalescing edit (a colour change or a nudge) and its mark: repeating it on the same
    /// mark (trying swatches, dragging in the colour panel, holding an arrow key) joins its undo step.
    private var coalescing: (edit: String, mark: UUID)?
    private var clickedSelected = false
    private var dragging = false

    private var keyMonitor: Any?
    /// The running AI request; results from any other (cancelled) request are ignored.
    private var activeRequest: UUID?
    private var cancelActiveRequest: (@Sendable () -> Void)?
    private var requestTask: Task<Void, Never>?
    /// The provider the running request went to, so switching it off in Settings can stop it.
    private var requestBackend: AIBackend?
    private var settingsObservation: AnyCancellable?
    // OCR runs and a `claude` process starts as soon as the window opens, so Annotate only waits
    // on the model itself.
    private let recognition: Task<RecognizedScreenshot?, Never>
    private var claude: ClaudeSession?

    init(document: VocumeDocument, url documentURL: URL, image url: URL) {
        self.url = url
        self.documentURL = documentURL
        imageData = document.image
        image = NSImage(data: document.image) ?? NSImage()
        recognition = Task.detached { RecognizedScreenshot(contentsOf: url) }
        marks = document.state.marks
        crop = document.state.crop
        undoStack = document.undo
        redoStack = document.redo
        savedEdits = edits  // loading isn't an edit, though the didSets above counted it as one
        followSettings()
        // Settings can change while the window is open; `objectWillChange` fires before the new
        // values land, so act on the next run-loop turn.
        settingsObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.followSettings() } }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Not `self?.handleKey(event) ?? event`: that also passes on the keys handleKey swallowed
            // (its `nil`), so they reached the window too: arrows beeped, ⌘Z ran Edit ▸ Undo as well.
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    isolated deinit {
        keyMonitor.map(NSEvent.removeMonitor)
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        if event.keyCode == 53 {  // esc: cancel a running request first, then leave cropping, then deselect
            if isBusy {
                cancelAI()
                return nil
            }
            if tool == .crop {
                setTool(.select)
                return nil
            }
            select(nil)
            window?.makeFirstResponder(nil)
            return nil
        }
        if window?.firstResponder is NSTextView { return event }  // typing in a field
        if tool == .crop, event.keyCode == 36 || event.keyCode == 76 {  // ↩ applies the crop
            setTool(.select)
            return nil
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            switch chars {
            case "z", "Z": event.modifierFlags.contains(.shift) ? redo() : undo()
            case "=", "+": zoomIn()
            case "-": zoomOut()
            case "0": setZoom(1)
            case "9": zoomToFit()
            default: return event
            }
            return nil
        }
        let arrows: [UInt16: CGVector] = [
            123: CGVector(dx: -1, dy: 0), 124: CGVector(dx: 1, dy: 0),
            125: CGVector(dx: 0, dy: 1), 126: CGVector(dx: 0, dy: -1),
        ]
        if let direction = arrows[event.keyCode], selected != nil {
            nudge(by: direction, pixels: event.modifierFlags.contains(.shift) ? 10 : 1)
            return nil
        }
        if event.keyCode == 51 || event.keyCode == 117 {  // ⌫ / ⌦
            deleteSelected()
            return nil
        }
        if let tool = Tool.allCases.first(where: { $0.key == chars }) {
            setTool(tool)
            return nil
        }
        return event
    }

    // MARK: Editing

    func snapshot() {
        coalescing = nil
        undoStack.append(state)
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    /// Takes an undo snapshot unless this edit continues the previous one on the same mark.
    private func snapshot(coalescing edit: String, mark id: UUID) {
        guard coalescing?.edit != edit || coalescing?.mark != id else { return }
        snapshot()
        coalescing = (edit, id)
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        restoring = true
        defer { restoring = false }
        coalescing = nil
        redoStack.append(state)
        state = last
        select(nil)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        restoring = true
        defer { restoring = false }
        coalescing = nil
        undoStack.append(state)
        state = next
        select(nil)
    }

    func update(_ id: UUID, _ change: (inout Mark) -> Void) {
        if let index = marks.firstIndex(where: { $0.id == id }) { change(&marks[index]) }
    }

    func select(_ id: UUID?) {
        if id != editing { editing = nil }
        marks.removeAll { $0.isEmptyText && $0.id != id }
        selected = id
    }

    func deleteSelected() {
        guard let id = selected else { return }
        snapshot()
        marks.removeAll { $0.id == id }
        select(nil)
    }

    func clear() {
        snapshot()
        marks = []
        select(nil)
    }

    func setTool(_ newTool: Tool) {
        tool = newTool
        select(nil)
    }

    func setColor(_ name: String) {
        colorName = name
        guard let id = selected else { return }
        snapshot(coalescing: "color", mark: id)
        update(id) { $0.color = name }
    }

    // MARK: Crop

    private enum CropGesture {
        case draw, move, resize(UnitPoint)
    }
    /// The crop frame when the drag began, and what the drag does to it.
    private var cropGesture: (start: Mark, kind: CropGesture)?
    static let wholeImage = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// The part of the image on screen: all of it while cropping, so the frame can grow again.
    var visibleCrop: CGRect { tool == .crop ? Self.wholeImage : crop ?? Self.wholeImage }

    var visiblePixelSize: CGSize {
        CGSize(width: pixelSize.width * visibleCrop.width, height: pixelSize.height * visibleCrop.height)
    }

    /// The crop frame as a mark, so it resizes and constrains exactly like a box.
    private var cropFrame: Mark? { crop.map { Mark(kind: .crop, x: $0.minX, y: $0.minY, w: $0.width, h: $0.height) } }

    func resetCrop() {
        guard crop != nil else { return }
        snapshot()
        crop = nil
    }

    /// A press on a handle resizes the frame, inside it moves it, anywhere else draws a new one.
    private func beginCrop(at point: CGPoint, viewPoint: CGPoint, viewSize: CGSize) {
        if let frame = cropFrame, let grabbed = handle(at: viewPoint, in: viewSize) {
            cropGesture = (frame, .resize(grabbed))
        } else if let frame = cropFrame, frame.frame(in: viewSize).contains(viewPoint) {
            cropGesture = (frame, .move)
        } else {
            cropGesture = (Mark(kind: .crop, x: point.x, y: point.y, w: 0, h: 0), .draw)
        }
    }

    private func dragCrop(to point: CGPoint, by delta: CGVector, constrained: Bool, aspect: Double) {
        guard let (start, gesture) = cropGesture else { return }
        var frame = start
        switch gesture {
        case .draw:
            frame.w = point.x - start.x
            frame.h = point.y - start.y
            if constrained { frame.constrain(aspect: aspect) }
        case .move:
            frame.x = min(max(start.x + delta.dx, 0), 1 - (start.w ?? 0))
            frame.y = min(max(start.y + delta.dy, 0), 1 - (start.h ?? 0))
        case .resize(let handle):
            let from = start.point(of: handle, in: CGSize(width: 1, height: 1))
            frame.move(handle, to: CGPoint(x: min(max(from.x + delta.dx, 0), 1), y: min(max(from.y + delta.dy, 0), 1)))
            if constrained { frame.constrain(handle, from: start, aspect: aspect) }
        }
        frame.normalize()
        crop = frame.frame(in: CGSize(width: 1, height: 1)).intersection(Self.wholeImage)
    }

    /// A click (no drag) keeps the old crop; a frame around (nearly) everything is no crop.
    private func endCrop(moved: CGFloat) {
        if case .draw = cropGesture?.kind, moved < 4 { crop = undoStack.last?.crop }
        if let crop, crop.isNull || crop.width * crop.height > 0.999 { self.crop = nil }
        cropGesture = nil
    }

    // MARK: Zoom

    /// The zoom in effect: the set one, or the one that fits.
    var effectiveZoom: Double {
        guard zoom == nil, viewport.width > 0, viewport.height > 0 else { return zoom ?? 1 }
        let scale = window?.backingScaleFactor ?? 2
        return min(viewport.width / visiblePixelSize.width, viewport.height / visiblePixelSize.height) * scale
    }

    /// The print's size in points at the current zoom (`nil` when fitting).
    var zoomedSize: CGSize? {
        guard let zoom else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: visiblePixelSize.width / scale * zoom, height: visiblePixelSize.height / scale * zoom)
    }

    func zoomIn() { setZoom(Self.zoomSteps.first { $0 > effectiveZoom * 1.01 } ?? Self.zoomSteps.last!) }
    func zoomOut() { setZoom(Self.zoomSteps.last { $0 < effectiveZoom * 0.99 } ?? Self.zoomSteps.first!) }
    func zoomToFit() { zoom = nil }
    func setZoom(_ value: Double) { zoom = min(max(value, Self.zoomSteps.first!), Self.zoomSteps.last!) }

    /// Trackpad pinch: scales from the zoom in effect when the pinch began.
    func pinch(_ magnification: Double) {
        if pinchStart == nil { pinchStart = effectiveZoom }
        setZoom((pinchStart ?? 1) * magnification)
    }

    func endPinch() { pinchStart = nil }

    /// Moves the selected mark by whole image pixels (arrow keys: 1, with Shift 10).
    func nudge(by direction: CGVector, pixels: CGFloat) {
        guard let id = selected else { return }
        let (dx, dy) = (direction.dx * pixels / pixelSize.width, direction.dy * pixels / pixelSize.height)
        snapshot(coalescing: "nudge", mark: id)
        update(id) { mark in
            mark.x += dx
            mark.y += dy
            mark.points = mark.points?.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
    }

    func setSize(_ newSize: Double) {
        size = newSize
        guard let id = selected else { return }
        snapshot()
        update(id) { $0.size = newSize }
    }

    // MARK: Mouse

    /// A drag on the canvas. `viewSize` is the whole image's size on screen; `offset` moves the
    /// gesture's points there from the visible (cropped) part it was made on.
    func drag(_ value: DragGesture.Value, in viewSize: CGSize, offset: CGPoint = .zero) {
        let location = CGPoint(x: value.location.x + offset.x, y: value.location.y + offset.y)
        let startLocation = CGPoint(x: value.startLocation.x + offset.x, y: value.startLocation.y + offset.y)
        let point = CGPoint(
            x: min(max(location.x / viewSize.width, 0), 1),
            y: min(max(location.y / viewSize.height, 0), 1)
        )
        if !dragging {
            dragging = true
            snapshot()
            begin(
                at: CGPoint(x: startLocation.x / viewSize.width, y: startLocation.y / viewSize.height),
                viewPoint: startLocation,
                viewSize: viewSize
            )
        }
        // Shift squares boxes, snaps lines to 45° and keeps proportions while resizing.
        let constrained = NSEvent.modifierFlags.contains(.shift)
        let aspect = pixelSize.width / pixelSize.height
        let dx = (location.x - startLocation.x) / viewSize.width
        let dy = (location.y - startLocation.y) / viewSize.height
        if tool == .crop {
            dragCrop(to: point, by: CGVector(dx: dx, dy: dy), constrained: constrained, aspect: aspect)
            return
        }
        guard let id = active else { return }
        update(id) { mark in
            switch tool {
            case .select:
                guard let origin = dragStart else { return }
                if let dragged = resizing {
                    let start = origin.point(of: dragged, in: CGSize(width: 1, height: 1))
                    mark = origin
                    mark.move(dragged, to: CGPoint(x: min(max(start.x + dx, 0), 1), y: min(max(start.y + dy, 0), 1)))
                    if constrained { mark.constrain(dragged, from: origin, aspect: aspect) }
                    return
                }
                mark.x = origin.x + dx
                mark.y = origin.y + dy
                mark.points = origin.points?.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            case .pen:
                mark.points?.append(point)
            case .text, .step:
                mark.x = point.x
                mark.y = point.y
            case .arrow, .line, .box, .ellipse, .highlight, .redact:
                mark.w = point.x - mark.x
                mark.h = point.y - mark.y
                if constrained { mark.constrain(aspect: aspect) }
            case .crop:
                break  // handled above
            }
        }
    }

    private func begin(at point: CGPoint, viewPoint: CGPoint, viewSize: CGSize) {
        window?.makeFirstResponder(nil)  // so ⌫ and tool keys work after typing a prompt
        if tool == .crop {
            beginCrop(at: point, viewPoint: viewPoint, viewSize: viewSize)
            return
        }
        guard let kind = tool.markKind else {
            if let grabbed = handle(at: viewPoint, in: viewSize), let id = selected {
                clickedSelected = true  // a press without a drag still edits the label (an arrow's sits on a handle)
                active = id
                dragStart = marks.first { $0.id == id }
                resizing = grabbed
                return
            }
            let hit = marks.last { $0.bounds(in: viewSize).contains(viewPoint) }
            clickedSelected = hit != nil && hit?.id == selected
            select(hit?.id)
            active = hit?.id
            dragStart = hit
            return
        }
        var mark = Mark(kind: kind, x: point.x, y: point.y, color: colorName, size: size)
        if kind == .pen { mark.points = [point] }
        if kind == .text { mark.label = "" }
        marks.append(mark)
        active = mark.id
        select(kind == .text ? mark.id : nil)
        if kind == .text { editing = mark.id }
    }

    func end(_ value: DragGesture.Value) {
        dragging = false
        defer {
            active = nil
            dragStart = nil
            resizing = nil
        }
        let moved = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        if tool == .crop { endCrop(moved: moved) }
        if let id = active, let mark = marks.first(where: { $0.id == id }) {
            switch tool {
            case .select:
                if resizing != nil { update(id) { $0.normalize() } }
                if moved < 3 && clickedSelected {  // clicking a selected mark again edits its label
                    editing = id
                    return
                }
            case .pen:
                if (mark.points?.count ?? 0) < 2 { marks.removeAll { $0.id == id } }
            case .text, .step, .crop:
                break
            case .arrow, .line, .box, .ellipse, .highlight, .redact:
                if moved < 4 {
                    marks.removeAll { $0.id == id }
                } else {
                    update(id) { $0.normalize() }  // boxes always grow right/down
                }
            }
        }
        if state == undoStack.last { undoStack.removeLast() }  // nothing changed
    }

    /// Tracks which handle of the selected mark the pointer is over (`nil` location: it left).
    func hover(at location: CGPoint?, in viewSize: CGSize, offset: CGPoint = .zero) {
        let hovered =
            tool == .select || tool == .crop
            ? location.flatMap { handle(at: CGPoint(x: $0.x + offset.x, y: $0.y + offset.y), in: viewSize) } : nil
        if hovered != hoveredHandle { hoveredHandle = hovered }
    }

    /// The handle of the selected mark (or of the crop frame, while cropping) within reach of a
    /// point in view coordinates.
    private func handle(at viewPoint: CGPoint, in viewSize: CGSize) -> UnitPoint? {
        let target = tool == .crop ? cropFrame : selected.flatMap { id in marks.first { $0.id == id } }
        guard let mark = target else { return nil }
        let distance = { (candidate: UnitPoint) in
            let point = mark.point(of: candidate, in: viewSize)
            return hypot(point.x - viewPoint.x, point.y - viewPoint.y)
        }
        return mark.handles.filter { distance($0) <= 8 }.min { distance($0) < distance($1) }
    }

    // MARK: AI

    /// Keeps this window consistent with Settings: stops a request whose provider (or AI as a whole)
    /// was switched off, and starts or stops the pre-warmed Claude process to match.
    private func followSettings() {
        if isBusy, let backend = requestBackend, !settings.usable.contains(backend) {
            cancelAI(announce: false)
        }
        if settings.wantsWarmClaude {
            if claude?.isRunning != true { claude = ClaudeSession() }
        } else if let warm = claude {
            warm.cancel()
            claude = nil
        }
    }

    /// The provider a request goes to: the picked one when it's usable, else the first usable one.
    var activeBackend: AIBackend? {
        settings.usable.contains(backend) ? backend : settings.usable.first
    }

    func askAI() {
        guard !isBusy, let backend = activeBackend else { return }
        isBusy = true
        busySince = Date()
        stage = "Reading the text in your screenshot"
        error = ""
        let request = prompt
        let ollamaModel = settings.ollamaModel
        let url = url
        let recognition = recognition
        let id = UUID()
        requestBackend = backend
        // Each Claude session takes one request: use the warm one and start the next.
        let session = backend == .claude ? (claude?.isRunning == true ? claude : ClaudeSession()) : nil
        if session != nil { claude = ClaudeSession() }
        // Codex runs as a fresh process; create it here so Cancel can terminate it.
        let codex = Process()
        activeRequest = id
        cancelActiveRequest = {
            session?.cancel()
            if codex.isRunning { codex.terminate() }
        }
        requestTask = Task.detached {
            let screenshot = await recognition.value
            await MainActor.run { if self.activeRequest == id { self.stage = "\(backend.displayName) is annotating" } }
            let result: Result<RecognizedScreenshot.Checked, any Error>
            do {
                guard let screenshot else {
                    throw AnnotationError(description: "Couldn't read \(url.lastPathComponent)")
                }
                let prompt = AnnotationPrompt.make(request: request, textSummary: screenshot.textSummary)
                let reply = try await backend.ask(
                    prompt, image: url, claude: session, codex: codex, ollamaModel: ollamaModel)
                let requested = try AnnotationPrompt.parseMarks(from: reply)
                if requested.contains(where: { $0.kind == .redact }) {
                    await MainActor.run { if self.activeRequest == id { self.stage = "Checking the redactions" } }
                }
                result = .success(screenshot.checkingRedactions(screenshot.resolve(requested), requested: requested))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.finishAI(result, request: id) }
        }
    }

    /// Stops the running request; anything it still returns is ignored. `announce` shows the
    /// "cancelled" toast (off when Settings, not the user, stopped it).
    func cancelAI() { cancelAI(announce: true) }

    private func cancelAI(announce: Bool) {
        guard isBusy else { return }
        cancelActiveRequest?()
        requestTask?.cancel()  // stops an in-flight Ollama HTTP request
        activeRequest = nil
        cancelActiveRequest = nil
        requestTask = nil
        requestBackend = nil
        isBusy = false
        if announce { flash("Request cancelled") }
    }

    private func finishAI(_ result: Result<RecognizedScreenshot.Checked, any Error>, request: UUID) {
        guard request == activeRequest else { return }  // cancelled meanwhile
        activeRequest = nil
        cancelActiveRequest = nil
        requestTask = nil
        requestBackend = nil
        isBusy = false
        switch result {
        case .success(let checked) where checked.marks.isEmpty:
            error = "No marks: the AI returned none, or its text matches weren't found."
        case .success(let checked):
            snapshot()
            marks += checked.marks.filter { $0.kind != .crop }
            if let area = Mark.cropArea(of: checked.marks) { crop = area }
            if checked.unconfirmed > 0 {
                error = "Some text still turned up after three checks and was covered too; look over the redactions."
            } else if checked.repaired > 0 {
                flash("The check covered \(checked.repaired) more")
            }
        case .failure(let failure):
            error = "\(failure)"
        }
    }

    // MARK: Export

    /// The screenshot's size in pixels (its point size can differ on Retina captures).
    var pixelSize: CGSize {
        let rep = image.representations.first
        return CGSize(
            width: rep.map(\.pixelsWide).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.width),
            height: rep.map(\.pixelsHigh).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.height))
    }

    /// The image with all marks at full pixel resolution, cropped, as PNG.
    func renderedPNG() -> Data? {
        let (width, height) = (pixelSize.width, pixelSize.height)
        let marks = marks
        let renderer = ImageRenderer(
            content: Image(nsImage: image).resizable().frame(width: width, height: height)
                .overlay(Canvas { context, size in MarkRenderer.draw(marks, in: context, size: size) })
        )
        renderer.scale = 1
        guard var cgImage = renderer.cgImage else { return nil }
        if let crop {
            let area = CGRect(
                x: crop.minX * width, y: crop.minY * height, width: crop.width * width, height: crop.height * height)
            cgImage = cgImage.cropping(to: area.integral) ?? cgImage
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func copyImage() {
        guard let png = renderedPNG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        flash("Copied to clipboard")
    }

    /// Saves the annotated image as a PNG, or a copy of the document, via the save sheet.
    func save(as type: UTType = .png) {
        guard let window else { return }
        let png = type == .png ? renderedPNG() : nil
        guard type != .png || png != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = type == .png ? exportName : url.deletingPathExtension().lastPathComponent
        if type == .vocume { panel.message = "The document includes the original screenshot, under any redactions." }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if let png {
                    try png.write(to: destination)
                } else {
                    try self.document.write(to: destination)
                }
                self.flash("Saved \(destination.lastPathComponent)")
            } catch {
                self.error = "\(error)"
            }
        }
    }

    // MARK: Document

    private var document: VocumeDocument {
        var document = VocumeDocument(imageName: url.lastPathComponent, image: imageData)
        (document.state, document.undo, document.redo) = (state, undoStack, redoStack)
        return document
    }

    /// Saves once edits pause for a second, so a drag doesn't rewrite the file on every frame.
    private func edited() {
        edits += 1
        let edit = edits
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if self?.edits == edit { self?.saveDocument() }
        }
    }

    /// Writes the document if it is behind; `false` (with `error` set) if that failed.
    @discardableResult func saveDocument() -> Bool {
        guard edits != savedEdits else { return true }
        do {
            try document.write(to: documentURL)
            savedEdits = edits
            return true
        } catch {
            self.error = "Couldn't save \(documentURL.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    /// The file name an export gets: the capture's name plus " annotated".
    private var exportName: String { url.deletingPathExtension().lastPathComponent + " annotated.png" }

    /// The annotated image as a PNG file, for dragging into another app (Slack, a GitHub issue, Finder).
    func dragItem() -> NSItemProvider {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent(exportName)
        guard let png = renderedPNG(),
            (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
            (try? png.write(to: file)) != nil
        else { return NSItemProvider() }
        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
    }

    func flash(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}

extension UTType {
    /// `.vocume` documents, declared in Info.plist.
    static let vocume = UTType(exportedAs: "dev.icepuma.vocume.document")
}
