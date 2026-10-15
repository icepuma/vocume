import AppKit
import Combine
import SwiftUI
import VocumeCore

/// State and actions for one editor window.
///
/// `ObservableObject` rather than `@Observable`/`@State`: those are macros, and the Command Line
/// Tools ship without the SwiftUI macro plugin, so the app must build without them.
@MainActor final class EditorModel: ObservableObject {
    let url: URL
    let image: NSImage
    weak var window: NSWindow?

    @Published var marks: [Mark] = [] {
        didSet { if marks != oldValue { hasUnexportedChanges = true } }
    }
    /// Marks changed since the last copy or save; closing asks first, and the close button shows
    /// the standard "edited" dot.
    var hasUnexportedChanges = false {
        didSet { window?.isDocumentEdited = hasUnexportedChanges }
    }
    @Published private(set) var undoStack: [[Mark]] = []
    @Published private(set) var tool = Tool.arrow
    @Published private(set) var colorName = Palette.defaultName
    @Published private(set) var size = 1.0
    @Published private(set) var selected: UUID?
    @Published var editing: UUID?
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
    /// The mark the last colour change went to: further changes to it (trying swatches, dragging
    /// in the colour panel) join that change's undo step.
    private var colorTarget: UUID?
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

    init(url: URL) {
        self.url = url
        image = NSImage(contentsOf: url) ?? NSImage()
        recognition = Task.detached { RecognizedScreenshot(contentsOf: url) }
        followSettings()
        // Settings can change while the window is open; `objectWillChange` fires before the new
        // values land, so act on the next run-loop turn.
        settingsObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.followSettings() } }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    isolated deinit {
        keyMonitor.map(NSEvent.removeMonitor)
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        if event.keyCode == 53 {  // esc: cancel a running request first, then deselect
            if isBusy {
                cancelAI()
                return nil
            }
            select(nil)
            window?.makeFirstResponder(nil)
            return nil
        }
        if window?.firstResponder is NSTextView { return event }  // typing in a field
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            guard chars == "z" else { return event }
            undo()
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
        colorTarget = nil
        undoStack.append(marks)
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        colorTarget = nil
        marks = last
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
        if colorTarget != id {
            snapshot()
            colorTarget = id
        }
        update(id) { $0.color = name }
    }

    func setSize(_ newSize: Double) {
        size = newSize
        guard let id = selected else { return }
        snapshot()
        update(id) { $0.size = newSize }
    }

    // MARK: Mouse

    func drag(_ value: DragGesture.Value, in viewSize: CGSize) {
        let point = CGPoint(
            x: min(max(value.location.x / viewSize.width, 0), 1),
            y: min(max(value.location.y / viewSize.height, 0), 1)
        )
        if !dragging {
            dragging = true
            snapshot()
            begin(
                at: CGPoint(x: value.startLocation.x / viewSize.width, y: value.startLocation.y / viewSize.height),
                viewPoint: value.startLocation,
                viewSize: viewSize
            )
        }
        guard let id = active else { return }
        let dx = (value.location.x - value.startLocation.x) / viewSize.width
        let dy = (value.location.y - value.startLocation.y) / viewSize.height
        update(id) { mark in
            switch tool {
            case .select:
                guard let origin = dragStart else { return }
                if let dragged = resizing {
                    let start = origin.point(of: dragged, in: CGSize(width: 1, height: 1))
                    mark = origin
                    mark.move(dragged, to: CGPoint(x: min(max(start.x + dx, 0), 1), y: min(max(start.y + dy, 0), 1)))
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
            case .arrow, .box, .highlight, .redact:
                mark.w = point.x - mark.x
                mark.h = point.y - mark.y
            }
        }
    }

    private func begin(at point: CGPoint, viewPoint: CGPoint, viewSize: CGSize) {
        window?.makeFirstResponder(nil)  // so ⌫ and tool keys work after typing a prompt
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
            case .text, .step:
                break
            case .arrow, .box, .highlight, .redact:
                if moved < 4 {
                    marks.removeAll { $0.id == id }
                } else {
                    update(id) { $0.normalize() }  // boxes always grow right/down
                }
            }
        }
        if marks == undoStack.last { undoStack.removeLast() }  // nothing changed
    }

    /// Tracks which handle of the selected mark the pointer is over (`nil` location: it left).
    func hover(at location: CGPoint?, in viewSize: CGSize) {
        let hovered = tool == .select ? location.flatMap { handle(at: $0, in: viewSize) } : nil
        if hovered != hoveredHandle { hoveredHandle = hovered }
    }

    /// The selected mark's handle within reach of a point in view coordinates.
    private func handle(at viewPoint: CGPoint, in viewSize: CGSize) -> UnitPoint? {
        guard let id = selected, let mark = marks.first(where: { $0.id == id }) else { return nil }
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
            let result: Result<[Mark], any Error>
            do {
                guard let screenshot else {
                    throw AnnotationError(description: "Couldn't read \(url.lastPathComponent)")
                }
                let prompt = AnnotationPrompt.make(request: request, textSummary: screenshot.textSummary)
                let reply = try await backend.ask(
                    prompt, image: url, claude: session, codex: codex, ollamaModel: ollamaModel)
                result = .success(screenshot.resolve(try AnnotationPrompt.parseMarks(from: reply)))
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

    private func finishAI(_ result: Result<[Mark], any Error>, request: UUID) {
        guard request == activeRequest else { return }  // cancelled meanwhile
        activeRequest = nil
        cancelActiveRequest = nil
        requestTask = nil
        requestBackend = nil
        isBusy = false
        switch result {
        case .success(let new) where new.isEmpty:
            error = "No marks: the AI returned none, or its text matches weren't found."
        case .success(let new):
            snapshot()
            marks += new
        case .failure(let failure):
            error = "\(failure)"
        }
    }

    // MARK: Export

    /// The image with all marks, at the image's full pixel size, as PNG.
    func renderedPNG() -> Data? {
        let rep = image.representations.first
        let width = CGFloat(rep.map(\.pixelsWide).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.width))
        let height = CGFloat(rep.map(\.pixelsHigh).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.height))
        let marks = marks
        let renderer = ImageRenderer(
            content: Image(nsImage: image).resizable().frame(width: width, height: height)
                .overlay(Canvas { context, size in MarkRenderer.draw(marks, in: context, size: size) })
        )
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func copyImage() {
        guard let png = renderedPNG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        hasUnexportedChanges = false
        flash("Copied to clipboard")
    }

    /// Saves a PNG via the save sheet; `thenClose` closes the window once it's written.
    func save(thenClose: Bool = false) {
        guard let png = renderedPNG(), let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + " annotated.png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try png.write(to: destination)
                self.hasUnexportedChanges = false
                self.flash("Saved \(destination.lastPathComponent)")
                if thenClose { window.close() }
            } catch {
                self.error = "\(error)"
            }
        }
    }

    func flash(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}
