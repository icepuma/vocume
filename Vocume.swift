// Menu-bar app: opens each new screenshot (folder or clipboard) in an annotation editor.
// Draw arrows/boxes/text yourself, or ask `claude` / `codex` (subscription login) to annotate.
// Build the app and DMG: scripts/build.sh (see README). Quick dev build: swiftc -parse-as-library -O Vocume.swift -o vocume
// Check drawing: ./vocume --demo in.png out.png   Check the AI overlay: ./vocume --overlay out.png
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Data

struct Mark: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: String  // arrow, box, highlight, redact, pen, text, step
    var x: Double, y: Double  // fractions (0-1) of the image, so marks survive resizing
    var w: Double?, h: Double?
    var label: String?
    var color: String?
    var size: Double?
    var points: [CGPoint]?
    var match: String?  // AI only: text to find via OCR; resolved into positioned marks
    var word: Bool?, anyCase: Bool?  // match options: whole words only, ignore case
    enum CodingKeys: String, CodingKey { case type, x, y, w, h, label, color, size, points, match, word, anyCase }
}

extension Mark {
    // Lenient decode: AI marks that use "match" have no x/y.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Double.self, forKey: .w)
        h = try c.decodeIfPresent(Double.self, forKey: .h)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        size = try c.decodeIfPresent(Double.self, forKey: .size)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points)
        match = try c.decodeIfPresent(String.self, forKey: .match)
        word = try c.decodeIfPresent(Bool.self, forKey: .word)
        anyCase = try c.decodeIfPresent(Bool.self, forKey: .anyCase)
    }
}

let palette: [(String, Color)] = [
    ("red", Color(red: 1, green: 0.23, blue: 0.19)),
    ("orange", Color(red: 1, green: 0.58, blue: 0)),
    ("yellow", Color(red: 1, green: 0.8, blue: 0)),
    ("green", Color(red: 0.2, green: 0.78, blue: 0.35)),
    ("blue", Color(red: 0, green: 0.48, blue: 1)),
    ("purple", Color(red: 0.69, green: 0.32, blue: 0.87)),
    ("black", Color(white: 0.12)),
    ("white", .white),
]
func color(_ name: String?) -> Color { palette.first { $0.0 == name }?.1 ?? palette[0].1 }
func ink(_ name: String?) -> Color { name == "yellow" || name == "white" ? .black : .white }

enum Tool: String, CaseIterable {
    case select, arrow, box, highlight, redact, pen, text, step
    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .highlight: "highlighter"
        case .redact: "rectangle.inset.filled"
        case .pen: "scribble.variable"
        case .text: "textformat"
        case .step: "1.circle"
        }
    }
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .box: "r"
        case .highlight: "h"
        case .redact: "x"
        case .pen: "p"
        case .text: "t"
        case .step: "n"
        }
    }
}

let ownType = NSPasteboard.PasteboardType("dev.icepuma.vocume")  // marks our own clipboard writes
var ownFiles = Set<String>()  // files we saved, so the folder watcher skips them

// MARK: - Geometry (shared by drawing, hit-testing and export)

// Sizes scale with the image so the export looks like the editor.
func unit(_ s: CGSize) -> CGFloat { max(s.width, s.height) / 1000 }
func fontSize(_ m: Mark, _ s: CGSize) -> CGFloat { 16 * unit(s) * (m.size ?? 1) }

func ends(_ m: Mark, _ s: CGSize) -> (CGPoint, CGPoint) {
    (CGPoint(x: m.x * s.width, y: m.y * s.height),
     CGPoint(x: (m.x + (m.w ?? 0)) * s.width, y: (m.y + (m.h ?? 0)) * s.height))
}

func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}

func labelRect(_ m: Mark, _ s: CGSize) -> CGRect {
    let f = fontSize(m, s), u = unit(s) * (m.size ?? 1), (a, b) = ends(m, s)
    let text = (m.label ?? "").isEmpty ? "Text" : m.label!
    let t = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: f, weight: .semibold)]).size()
    let size = CGSize(width: t.width + f, height: t.height + f * 0.6)
    let (p, anchor): (CGPoint, UnitPoint) = switch m.type {
    case "text": (a, .topLeading)
    case "arrow": (a, .center)  // label sits on the tail, arrow points at the thing
    case "step": (CGPoint(x: a.x + 18 * u, y: a.y), .leading)
    case "pen": (a, .bottomLeading)
    default: (CGPoint(x: rect(a, b).minX, y: rect(a, b).minY - 6 * u), .bottomLeading)
    }
    return CGRect(origin: CGPoint(x: p.x - size.width * anchor.x, y: p.y - size.height * anchor.y), size: size)
}

func penPoints(_ m: Mark, _ s: CGSize) -> [CGPoint] {
    (m.points ?? []).map { CGPoint(x: $0.x * s.width, y: $0.y * s.height) }
}

func bounds(_ m: Mark, _ s: CGSize) -> CGRect {
    let (a, b) = ends(m, s), u = unit(s) * (m.size ?? 1)
    if m.type == "text" { return labelRect(m, s).insetBy(dx: -4, dy: -4) }
    var r = switch m.type {
    case "step": CGRect(x: a.x - 14 * u, y: a.y - 14 * u, width: 28 * u, height: 28 * u)
    case "pen": penPoints(m, s).reduce(CGRect(origin: a, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    default: rect(a, b)
    }
    r = r.insetBy(dx: -6 * u, dy: -6 * u)
    if let l = m.label, !l.isEmpty { r = r.union(labelRect(m, s)) }
    return r
}

func draw(_ ctx: GraphicsContext, _ s: CGSize, _ marks: [Mark], selected: UUID? = nil, editing: UUID? = nil) {
    let u0 = unit(s)
    var step = 0
    for m in marks {
        let c = color(m.color), u = u0 * (m.size ?? 1), lw = 6 * u
        let (a, b) = ends(m, s)
        var g = ctx
        g.addFilter(.shadow(color: .black.opacity(0.35), radius: 3 * u0, y: u0))
        switch m.type {
        case "arrow":
            let ang = atan2(b.y - a.y, b.x - a.x), head = lw * 3.6
            var line = Path()
            line.move(to: a)
            line.addLine(to: CGPoint(x: b.x - cos(ang) * head * 0.8, y: b.y - sin(ang) * head * 0.8))
            g.stroke(line, with: .color(c), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            var tip = Path()
            tip.move(to: b)
            tip.addLine(to: CGPoint(x: b.x - cos(ang - 0.45) * head, y: b.y - sin(ang - 0.45) * head))
            tip.addLine(to: CGPoint(x: b.x - cos(ang + 0.45) * head, y: b.y - sin(ang + 0.45) * head))
            tip.closeSubpath()
            g.fill(tip, with: .color(c))
        case "highlight":
            var h = ctx
            h.blendMode = .multiply
            h.fill(Path(roundedRect: rect(a, b), cornerRadius: 2 * u0), with: .color(c.opacity(0.45)))
        case "redact":
            ctx.fill(Path(roundedRect: rect(a, b), cornerRadius: 3 * u0), with: .color(c))
        case "pen":
            var p = Path()
            p.addLines(penPoints(m, s))
            g.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        case "step":
            step += 1
            let r = CGRect(x: a.x - 14 * u, y: a.y - 14 * u, width: 28 * u, height: 28 * u)
            g.fill(Path(ellipseIn: r), with: .color(c))
            ctx.stroke(Path(ellipseIn: r.insetBy(dx: u, dy: u)), with: .color(.white.opacity(0.9)), lineWidth: 2 * u)
            ctx.draw(Text("\(step)").font(.system(size: 15 * u, weight: .bold, design: .rounded)).foregroundStyle(ink(m.color)), at: a)
        case "text":
            break
        default:
            g.stroke(Path(roundedRect: rect(a, b), cornerRadius: 4 * u0), with: .color(c), lineWidth: lw)
        }
        if let l = m.label, !l.isEmpty, m.id != editing {
            let r = labelRect(m, s)
            g.fill(Path(roundedRect: r, cornerRadius: r.height * 0.3), with: .color(c))
            ctx.draw(Text(l).font(.system(size: fontSize(m, s), weight: .semibold)).foregroundStyle(ink(m.color)),
                     at: CGPoint(x: r.midX, y: r.midY))
        }
        if m.id == selected {
            ctx.stroke(Path(roundedRect: bounds(m, s), cornerRadius: 4), with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }
}

// MARK: - Editor state

// ObservableObject instead of @State: Command Line Tools ship without the SwiftUI macro plugin.
final class Model: ObservableObject {
    let url: URL
    let image: NSImage
    weak var window: NSWindow?
    @Published var marks: [Mark] = []
    @Published var undoStack: [[Mark]] = []
    @Published var tool = Tool.arrow
    @Published var colorName = "red"
    @Published var size = 1.0
    @Published var selected: UUID?
    @Published var editing: UUID?
    @Published var prompt = ""
    @Published var backend = "claude"
    @Published var busy = false
    @Published var stage = ""  // what the AI step is doing, shown in the overlay
    @Published var busySince = Date()
    @Published var error = ""
    @Published var toast: String?
    private var active: UUID?, dragStart: Mark?, clickedSelected = false, dragging = false
    private var monitor: Any?
    // Speed: OCR runs and a `claude` process starts the moment the window opens, so Annotate only waits on the model.
    private let prep: Task<([VNRecognizedText], Pixels?), Never>
    private var warm = WarmClaude()

    init(url: URL) {
        self.url = url
        image = NSImage(contentsOf: url) ?? NSImage()
        prep = Task.detached { (ocr(url), Pixels(url)) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }
    }
    deinit { monitor.map(NSEvent.removeMonitor) }

    func key(_ e: NSEvent) -> NSEvent? {
        guard e.window === window else { return e }
        if e.keyCode == 53 { select(nil); window?.makeFirstResponder(nil); return nil }  // esc
        if window?.firstResponder is NSTextView { return e }  // typing in a field
        let chars = e.charactersIgnoringModifiers ?? ""
        if e.modifierFlags.contains(.command) {
            if chars == "z" { undo(); return nil }
            return e
        }
        if e.keyCode == 51 || e.keyCode == 117 { deleteSelected(); return nil }  // ⌫ / ⌦
        if let t = Tool.allCases.first(where: { $0.key == chars }) { setTool(t); return nil }
        return e
    }

    func snapshot() {
        undoStack.append(marks)
        if undoStack.count > 200 { undoStack.removeFirst() }
    }
    func undo() {
        guard let last = undoStack.popLast() else { return }
        marks = last
        select(nil)
    }
    func update(_ id: UUID, _ f: (inout Mark) -> Void) {
        if let i = marks.firstIndex(where: { $0.id == id }) { f(&marks[i]) }
    }
    func select(_ id: UUID?) {
        if id != editing { editing = nil }
        marks.removeAll { $0.type == "text" && ($0.label ?? "").isEmpty && $0.id != id }
        selected = id
    }
    func deleteSelected() {
        guard let id = selected else { return }
        snapshot()
        marks.removeAll { $0.id == id }
        select(nil)
    }
    func clear() { snapshot(); marks = []; select(nil) }
    func setTool(_ t: Tool) { tool = t; select(nil) }
    func setColor(_ c: String) {
        colorName = c
        if let id = selected { snapshot(); update(id) { $0.color = c } }
    }
    func setSize(_ k: Double) {
        size = k
        if let id = selected { snapshot(); update(id) { $0.size = k } }
    }

    // MARK: Mouse

    func drag(_ v: DragGesture.Value, _ s: CGSize) {
        let p = CGPoint(x: min(max(v.location.x / s.width, 0), 1), y: min(max(v.location.y / s.height, 0), 1))
        if !dragging {
            dragging = true
            snapshot()
            begin(CGPoint(x: v.startLocation.x / s.width, y: v.startLocation.y / s.height), v.startLocation, s)
        }
        guard let id = active else { return }
        let dx = (v.location.x - v.startLocation.x) / s.width, dy = (v.location.y - v.startLocation.y) / s.height
        update(id) { m in
            switch tool {
            case .select:
                guard let o = dragStart else { return }
                m.x = o.x + dx
                m.y = o.y + dy
                m.points = o.points?.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            case .pen: m.points?.append(p)
            case .text, .step: m.x = p.x; m.y = p.y
            default: m.w = p.x - m.x; m.h = p.y - m.y
            }
        }
    }

    private func begin(_ p: CGPoint, _ viewPoint: CGPoint, _ s: CGSize) {
        window?.makeFirstResponder(nil)  // so ⌫ / tool keys work after typing a prompt
        if tool == .select {
            let hit = marks.last(where: { bounds($0, s).contains(viewPoint) })
            clickedSelected = hit != nil && hit?.id == selected
            select(hit?.id)
            active = hit?.id
            dragStart = hit
            return
        }
        var m = Mark(type: tool.rawValue, x: p.x, y: p.y, color: colorName, size: size)
        if tool == .pen { m.points = [p] }
        if tool == .text { m.label = "" }
        marks.append(m)
        active = m.id
        select(tool == .text ? m.id : nil)
        if tool == .text { editing = m.id }
    }

    func end(_ v: DragGesture.Value, _ s: CGSize) {
        dragging = false
        defer { active = nil; dragStart = nil }
        let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
        if let id = active, let m = marks.first(where: { $0.id == id }) {
            switch tool {
            case .select:
                if moved < 3 && clickedSelected { editing = id; return }  // click a selected mark again to label it
            case .pen:
                if (m.points?.count ?? 0) < 2 { marks.removeAll { $0.id == id } }
            case .text, .step:
                break
            default:
                if moved < 4 {
                    marks.removeAll { $0.id == id }
                } else if tool != .arrow {
                    update(id) { m in
                        m.x = min(m.x, m.x + (m.w ?? 0)); m.w = abs(m.w ?? 0)
                        m.y = min(m.y, m.y + (m.h ?? 0)); m.h = abs(m.h ?? 0)
                    }
                }
            }
        }
        if marks == undoStack.last { undoStack.removeLast() }  // nothing changed
    }

    // MARK: AI

    func ask() {
        guard !busy else { return }
        busy = true
        busySince = Date()
        stage = "Reading the text in your screenshot"
        error = ""
        let name = backend == "claude" ? "Claude" : "Codex"
        let request = prompt.isEmpty ? "Point out anything that looks wrong or noteworthy." : prompt
        let backend = backend, url = url, prep = prep
        // Use the warm process (each takes one request), and start the next one for later.
        let claude = backend == "claude" ? (warm.p.isRunning ? warm : WarmClaude()) : nil
        if claude != nil { warm = WarmClaude() }
        Task.detached {
            let (texts, px) = await prep.value
            await MainActor.run { self.stage = "\(name) is annotating" }
            let r = Result { () throws -> [Mark] in
                guard let px else { throw Failure(description: "Couldn't read \(url.lastPathComponent)") }
                return resolve(try runAI(aiPrompt(request, texts), url, claude: claude), texts, px)
            }
            await MainActor.run {
                self.busy = false
                switch r {
                case .success(let new) where new.isEmpty: self.error = "No marks: the AI returned none, or its text matches weren't found."
                case .success(let new): self.snapshot(); self.marks += new
                case .failure(let e): self.error = "\(e)"
                }
            }
        }
    }

    // MARK: Export

    @MainActor func rendered() -> Data? {
        let rep = image.representations.first
        let w = CGFloat(rep.map(\.pixelsWide).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.width))
        let h = CGFloat(rep.map(\.pixelsHigh).flatMap { $0 > 0 ? $0 : nil } ?? Int(image.size.height))
        let marks = marks
        let r = ImageRenderer(content: Image(nsImage: image).resizable().frame(width: w, height: h)
            .overlay(Canvas { ctx, s in draw(ctx, s, marks) }))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    @MainActor func copyImage() {
        guard let png = rendered() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        pb.setData(Data(), forType: ownType)
        flash("Copied to clipboard")
    }

    @MainActor func save() {
        guard let png = rendered(), let window else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + " annotated.png"
        p.beginSheetModal(for: window) { r in
            guard r == .OK, let u = p.url else { return }
            ownFiles.insert(u.lastPathComponent)
            do { try png.write(to: u); self.flash("Saved \(u.lastPathComponent)") } catch { self.error = "\(error)" }
        }
    }

    func flash(_ t: String) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toast == t { self?.toast = nil }
        }
    }
}

// MARK: - UI

struct EditorView: View {
    @ObservedObject var m: Model
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: m.image).resizable().aspectRatio(contentMode: .fit)
                    .overlay { GeometryReader { g in canvas(g.size) } }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    .padding(28)
            }
            .overlay(alignment: .top) {
                if let t = m.toast {
                    Label(t, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: m.toast)
            Divider()
            aiBar
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 2) {
                ForEach(Tool.allCases, id: \.self) { t in
                    Button { m.setTool(t) } label: {
                        Image(systemName: t.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 28)
                            .foregroundStyle(m.tool == t ? Color.accentColor : .primary)
                            .background(m.tool == t ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(t.rawValue.capitalized)  \(t.key.uppercased())")
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 4) {
                ForEach(palette, id: \.0) { p in
                    Circle().fill(p.1)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(Circle().strokeBorder(m.colorName == p.0 ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Circle())
                        .onTapGesture { m.setColor(p.0) }
                        .help(p.0.capitalized)
                }
            }

            Picker("Size", selection: Binding(get: { m.size }, set: { m.setSize($0) })) {
                Text("S").tag(0.6)
                Text("M").tag(1.0)
                Text("L").tag(1.6)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 96).help("Size")

            Spacer()

            HStack(spacing: 12) {
                Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo  ⌘Z").disabled(m.undoStack.isEmpty)
                Button { m.deleteSelected() } label: { Image(systemName: "trash") }
                    .help("Delete selected  ⌫").disabled(m.selected == nil)
                Button { m.clear() } label: { Image(systemName: "xmark.bin") }
                    .help("Clear all").disabled(m.marks.isEmpty)
            }
            .buttonStyle(.borderless).imageScale(.large)

            HStack(spacing: 8) {
                Button { m.copyImage() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy annotated image  ⇧⌘C")
                Button { m.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s").buttonStyle(.borderedProminent).help("Save annotated image  ⌘S")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
    }

    var aiBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !m.error.isEmpty {
                Text(m.error).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.purple).imageScale(.large)
                Picker("Model", selection: $m.backend) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                }
                .labelsHidden().fixedSize().disabled(m.busy)
                HStack(spacing: 10) {
                    TextField("Ask AI to annotate, e.g. “point out UI bugs”", text: $m.prompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(m.ask)
                    Button("Annotate", action: m.ask)
                }
                .disabled(m.busy)
                .overlay {
                    if m.busy {
                        ThinkingOverlay(stage: m.stage, since: m.busySince)
                            .padding(-2)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.spring(duration: 0.4), value: m.busy)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
    }

    func canvas(_ s: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in draw(ctx, size, m.marks, selected: m.selected, editing: m.editing) }
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { m.drag($0, s) }
                    .onEnded { m.end($0, s) })
                .pointerStyle(m.tool == .select ? .default : .rectSelection)
            if let id = m.editing, let mark = m.marks.first(where: { $0.id == id }) {
                let r = labelRect(mark, s), f = fontSize(mark, s)
                TextField("Text", text: Binding(
                    get: { m.marks.first { $0.id == id }?.label ?? "" },
                    set: { v in m.update(id) { $0.label = v } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: f, weight: .semibold))
                    .foregroundStyle(ink(mark.color))
                    .padding(.horizontal, f * 0.5).padding(.vertical, f * 0.3)
                    .background(color(mark.color), in: RoundedRectangle(cornerRadius: r.height * 0.3))
                    .fixedSize()
                    .offset(x: r.minX, y: r.minY)
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .onSubmit { m.select(nil) }
                    .id(id)
            }
        }
    }
}

// MARK: - OCR (models can't place marks on single letters; Vision can)

func ocr(_ url: URL) -> [VNRecognizedText] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    try? VNImageRequestHandler(url: url).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first }
}

// Vision rects are normalized with a bottom-left origin; marks use top-left.
// Only the whole-line box is precise; Vision's boxes for parts of a line drift by a letter or two.
func lineBox(_ t: VNRecognizedText) -> CGRect? {
    guard let b = (try? t.boundingBox(for: t.string.startIndex..<t.string.endIndex))??.boundingBox else { return nil }
    return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
}

// RGBA copy of the screenshot, so OCR estimates can snap to the real letter pixels.
struct Pixels {
    let w: Int, h: Int, rgba: [UInt8]

    init?(_ url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
                                      bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            return true
        }
        guard ok else { return nil }
        (w, h, rgba) = (img.width, img.height, buf)
    }

    // Per pixel column of `r`: does it hold ink, i.e. a colour clearly unlike the background
    // (the most common colour in `r`)? Works for dark-on-light and light-on-dark alike.
    func ink(_ r: CGRect) -> (x0: Int, cols: [Bool]) {
        let x0 = max(Int(r.minX * Double(w)), 0), x1 = min(Int(r.maxX * Double(w)), w)
        let y0 = max(Int(r.minY * Double(h)), 0), y1 = min(Int(r.maxY * Double(h)), h)
        guard x1 > x0, y1 > y0 else { return (x0, []) }
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
        }
        var counts: [Int: Int] = [:]
        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let (r, g, b) = at(x, y)
                counts[(r >> 4) << 8 | (g >> 4) << 4 | b >> 4, default: 0] += 1
            }
        }
        let k = counts.max { $0.value < $1.value }?.key ?? 0
        let bg = ((k >> 8) * 16 + 8, (k >> 4 & 15) * 16 + 8, (k & 15) * 16 + 8)
        let cols = (x0..<x1).map { x in
            (y0..<y1).contains { y in
                let (r, g, b) = at(x, y)
                return max(abs(r - bg.0), abs(g - bg.1), abs(b - bg.2)) > 72
            }
        }
        return (x0, cols)
    }
}

// One OCR line measured against the pixels: its ink columns, plus each word's real pixel span.
struct Line {
    let text: String, box: CGRect, x0: Int, ink: [Bool]
    var words: [(chars: Range<String.Index>, px: Range<Int>)] = []

    init?(_ t: VNRecognizedText, _ px: Pixels) {
        guard let box = lineBox(t) else { return nil }
        text = t.string
        self.box = box
        let lineH = box.height * Double(px.h)
        (x0, ink) = px.ink(box.insetBy(dx: -lineH * 0.1 / Double(px.w), dy: 0))
        // Glyphs are runs of ink columns; runs closer than a space belong to the same word.
        var blobs: [Range<Int>] = []
        var start: Int?
        for (i, on) in (ink + [false]).enumerated() {
            if on, start == nil { start = i }
            if !on, let s = start {
                if let last = blobs.last, s - last.upperBound < max(2, Int(lineH * 0.15)) {
                    blobs[blobs.count - 1] = last.lowerBound..<i
                } else {
                    blobs.append(s..<i)
                }
                start = nil
            }
        }
        let chars = text.split(whereSeparator: \.isWhitespace).map { $0.startIndex..<$0.endIndex }
        // ponytail: if gaps don't line up 1:1 with words (icons, odd spacing), locate() slices the whole line instead.
        if chars.count == blobs.count {
            words = zip(chars, blobs).map { ($0, $1.lowerBound + x0..<$1.upperBound + x0) }
        }
    }

    // Box for text[r]: estimate inside its words' real pixel span, then snap to actual glyph edges.
    func locate(_ r: Range<String.Index>, _ px: Pixels) -> CGRect {
        let W = Double(px.w)
        var ref = text.startIndex..<text.endIndex
        var (s0, s1) = (box.minX * W, box.maxX * W)
        if let a = words.first(where: { $0.chars.contains(r.lowerBound) }),
           let b = words.first(where: { $0.chars.contains(text.index(before: r.upperBound)) }) {
            ref = a.chars.lowerBound..<b.chars.upperBound
            (s0, s1) = (Double(a.px.lowerBound), Double(b.px.upperBound))
        }
        func on(_ x: Int) -> Bool { ink.indices.contains(x - x0) && ink[x - x0] }
        let cols = Int(s0)..<max(Int(s1.rounded(.up)), Int(s0))

        // Exact case: one ink run per letter (monospace, most UI text), so letters map straight to runs.
        let letters = text[ref].indices.filter { !text[$0].isWhitespace }
        var glyphs: [Range<Int>] = []
        var g: Int?
        for x in cols.lowerBound...cols.upperBound {
            if on(x), g == nil { g = x }
            if !on(x), let st = g { glyphs.append(st..<x); g = nil }
        }
        if glyphs.count == letters.count,
           let i0 = letters.firstIndex(where: { $0 >= r.lowerBound }),
           let i1 = letters.lastIndex(where: { $0 < r.upperBound }), i0 <= i1 {
            let a = Double(glyphs[i0].lowerBound), b = Double(glyphs[i1].upperBound)
            return CGRect(x: a / W, y: box.minY, width: (b - a) / W, height: box.height)
        }

        // Otherwise (touching letters, quotes…): estimate with system-font widths, then snap to nearby glyph edges.
        let width = { (s: Substring) in NSAttributedString(string: String(s), attributes: [.font: NSFont.systemFont(ofSize: 100)]).size().width }
        let total = max(width(text[ref]), 1)
        let e0 = s0 + (s1 - s0) * width(text[ref.lowerBound..<r.lowerBound]) / total
        let e1 = s0 + (s1 - s0) * width(text[ref.lowerBound..<r.upperBound]) / total
        let starts = cols.filter { on($0) && !on($0 - 1) }.map(Double.init)
        let ends = cols.filter { on($0) && !on($0 + 1) }.map { Double($0 + 1) }
        // Only snap to an edge near the estimate; touching letters have no edge between them.
        let tol = max((e1 - e0) * 0.5, 2)
        let a = starts.min { abs($0 - e0) < abs($1 - e0) }.flatMap { abs($0 - e0) <= tol ? $0 : nil } ?? e0
        let b = ends.filter { $0 > a }.min { abs($0 - e1) < abs($1 - e1) }.flatMap { abs($0 - e1) <= tol ? $0 : nil } ?? e1
        return CGRect(x: a / W, y: box.minY, width: max(b - a, 1) / W, height: box.height)
    }
}

// Each {"match": ...} mark becomes one positioned mark per occurrence of that text.
func resolve(_ marks: [Mark], _ texts: [VNRecognizedText], _ px: Pixels) -> [Mark] {
    guard marks.contains(where: { $0.match != nil }) else { return marks }
    let lines = texts.compactMap { Line($0, px) }
    return marks.flatMap { m -> [Mark] in
        guard let q = m.match, !q.isEmpty else { return [m] }
        var pattern = NSRegularExpression.escapedPattern(for: q)
        if m.word == true { pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])" }
        guard let re = try? NSRegularExpression(pattern: pattern, options: m.anyCase == true ? .caseInsensitive : []) else { return [] }
        return lines.flatMap { l in
            re.matches(in: l.text, range: NSRange(l.text.startIndex..., in: l.text))
                .compactMap { Range($0.range, in: l.text) }
                .map { place(m, l.locate($0, px), px) }
        }
    }
}

func place(_ m: Mark, _ b: CGRect, _ px: Pixels) -> Mark {
    var m = m
    m.id = UUID()
    m.match = nil
    // Work in pixels so padding is even on both axes: tight for covers, roomier for boxes.
    let W = Double(px.w), H = Double(px.h), lineH = b.height * H
    let pad = lineH * (m.type == "box" ? 0.3 : 0.06)
    let r = b.insetBy(dx: -pad / W, dy: -pad / H)
    switch m.type {
    case "arrow":  // points at the text from up-left
        m.x = r.minX - 2.5 * lineH / W; m.y = r.midY - 1.5 * lineH / H
        m.w = 2.3 * lineH / W; m.h = 1.5 * lineH / H
    case "step": m.x = r.minX - 0.8 * lineH / W; m.y = r.midY
    case "text": m.x = r.minX; m.y = r.maxY + pad / H
    default: m.x = r.minX; m.y = r.minY; m.w = r.width; m.h = r.height
    }
    return m
}

func aiPrompt(_ request: String, _ texts: [VNRecognizedText]) -> String {
    let lines = texts.prefix(300).compactMap { t -> String? in
        guard let b = lineBox(t) else { return nil }
        return String(format: "%.3f,%.3f,%.3f,%.3f  ", b.minX, b.minY, b.width, b.height) + t.string
    }.joined(separator: "\n")
    return """
    You annotate a screenshot using an annotation app's tools. The user's request: \(request)

    The screenshot is attached. Respond with ONLY a JSON array, no prose. Each item has:
    - "type": "arrow" | "box" | "highlight" (translucent marker) | "redact" (solid filled block that hides content) \
    | "pen" (freehand line) | "text" (a note) | "step" (auto-numbered circle 1, 2, 3…)
    - a position, either:
      - "match": exact text to find. The app places one mark on EVERY occurrence, precisely, via OCR. \
    Prefer this whenever the target is visible text, even a single letter. Case-sensitive unless "anyCase": true. \
    Also matches inside longer words ("on" hits "only") unless "word": true (whole words only).
      - or "x","y","w","h": fractions 0-1 of image width/height, origin top-left. box/highlight/redact: the rectangle. \
    arrow: from (x,y) to (x+w,y+h), tip at the end. text/step: x,y is the spot. pen: "points": [[x,y], …] instead.
    - "color": red | orange | yellow | green | blue | purple | black | white (default red)
    - "size": 0.6 small, 1 medium, 1.6 large (default 1)
    - "label": short note shown in a coloured pill. Only include it when a note helps; never for plain \
    redactions or highlights. Required for "text" (it is the text).
    Example: [{"type":"redact","match":"o","color":"white"},{"type":"arrow","x":0.2,"y":0.3,"w":0.1,"h":0.05,"label":"bug here"}]

    Text found by OCR (x,y,w,h then the text). Use it to place marks accurately:
    \(lines.isEmpty ? "(none)" : lines)
    """
}

// Claude Code's keyword rainbow: theme keys rainbow_red…rainbow_violet and their lighter *_shimmer
// variants (identical in its light and dark themes).
let rainbow: [Color] = [(235.0, 95.0, 87.0), (245, 139, 87), (250, 195, 95), (145, 200, 130), (130, 170, 220), (155, 130, 200), (200, 130, 180)]
    .map { Color(red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }
let rainbowShimmer: [Color] = [(250.0, 155.0, 147.0), (255, 185, 137), (255, 225, 155), (185, 230, 180), (180, 205, 240), (195, 180, 230), (230, 180, 210)]
    .map { Color(red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }

// Covers the prompt field while the AI works, animated the way Claude Code animates its ultra*
// keywords: each character takes the next rainbow colour, and a 3-character glimmer band of the
// shimmer colours sweeps left→right at 1 char / 50 ms (from 10 chars before the text to 10 after),
// stepped on Claude Code's 64 ms animation tick. The border is its scrolling rainbow rule
// (segment i gets rainbow[i + t/150]). It swallows clicks, so nothing new can be entered.
struct ThinkingOverlay: View {
    let stage: String
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let ms = Int(tl.date.timeIntervalSince(since) * 1000) / 64 * 64
            let chars = Array(stage + "…")
            let glimmer = reduceMotion ? -100 : -10 + (ms / 50) % (chars.count + 20)  // -100 = parked off-screen, as in Claude Code
            let phase = reduceMotion ? 0 : ms / 150
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack(spacing: 8) {
                Text("✻").foregroundStyle(rainbow[phase % 7])
                chars.enumerated().reduce(Text("")) { line, c in
                    let color = abs(c.offset - glimmer) <= 1 ? rainbowShimmer[c.offset % 7] : rainbow[c.offset % 7]
                    return Text("\(line)\(Text(String(c.element)).foregroundStyle(color))")
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%.1fs", tl.date.timeIntervalSince(since))).foregroundStyle(.secondary)
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

// The rounded border drawn as a row of terminal-cell-sized segments in scrolling rainbow colours.
struct RainbowRule: View {
    let phase: Int
    var body: some View {
        Canvas { ctx, size in
            let path = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 8, style: .continuous)
            let n = max(Int((size.width + size.height) * 2 / 9), 7)  // ~9 pt per segment, like a "─" cell
            for k in 0..<n {
                ctx.stroke(path.trimmedPath(from: Double(k) / Double(n), to: Double(k + 1) / Double(n)),
                           with: .color(rainbow[(k + phase) % 7]), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CLI bridge

struct Failure: Error, CustomStringConvertible { let description: String }

// Asks Claude (pre-started process) or, with `claude == nil`, Codex.
func runAI(_ prompt: String, _ img: URL, claude: WarmClaude?) throws -> [Mark] {
    let reply: String
    if let claude {
        // Original resolution: quality over speed, the CLI downsizes only if the model needs it.
        guard let data = try? Data(contentsOf: img) else { throw Failure(description: "Couldn't read \(img.lastPathComponent)") }
        reply = try claude.ask(prompt, image: data, type: UTType(filenameExtension: img.pathExtension)?.preferredMIMEType ?? "image/png")
    } else {
        // Your configured model and reasoning effort (quality over speed); only MCP servers are
        // skipped, since this task never uses them and starting them costs seconds.
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stdout = try sh(["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-c", "mcp_servers={}",
                             "--image=\(img.path)", "--output-last-message=\(out.path)", prompt],
                            cwd: img.deletingLastPathComponent())
        reply = (try? String(contentsOf: out, encoding: .utf8)) ?? stdout
    }
    guard let a = reply.firstIndex(of: "["), let b = reply.lastIndex(of: "]") else { throw Failure(description: reply) }
    return try JSONDecoder().decode([Mark].self, from: Data(reply[a...b].utf8))
}

// A `claude` process started ahead of time (saves ~1s+ of CLI startup, costs no quality), waiting for one request.
// --safe-mode skips plugins/hooks/MCP but keeps your subscription login (--bare needs an API key);
// the image goes inline, so Claude needs no tools and no extra turn to read a file.
final class WarmClaude {
    let p = Process(), input = Pipe(), output = Pipe()

    init() {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--safe-mode", "--tools", "", "--no-session-persistence",
                       "--system-prompt", "You annotate screenshots. Output only the JSON array requested."]
        p.environment = cliEnv()
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
    deinit { if p.isRunning { p.terminate() } }

    func ask(_ prompt: String, image: Data, type: String) throws -> String {
        guard p.isRunning else { throw Failure(description: "claude didn't start (installed and logged in?)") }
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": [
            ["type": "image", "source": ["type": "base64", "media_type": type, "data": image.base64EncodedString()]],
            ["type": "text", "text": prompt],
        ]]]
        try input.fileHandleForWriting.write(contentsOf: try JSONSerialization.data(withJSONObject: msg) + Data("\n".utf8))
        defer { try? input.fileHandleForWriting.close() }
        var buf = Data()
        while true {  // one JSON event per line; stop at the result
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { throw Failure(description: "claude exited without a result") }
            buf.append(chunk)
            while let nl = buf.firstIndex(of: 10) {
                let line = buf[..<nl]
                buf = Data(buf[(nl + 1)...])
                guard let ev = try? JSONSerialization.jsonObject(with: line) as? [String: Any], ev["type"] as? String == "result" else { continue }
                if ev["is_error"] as? Bool == true { throw Failure(description: "claude: \(ev["result"] ?? ev)") }
                return ev["result"] as? String ?? ""
            }
        }
    }
}

// GUI apps get a bare PATH; add the usual CLI install spots.
func cliEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let home = NSHomeDirectory()
    env["PATH"] = "\(home)/.local/bin:\(home)/.bun/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    return env
}

func sh(_ args: [String], cwd: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    p.currentDirectoryURL = cwd
    p.environment = cliEnv()
    let errFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: errFile.path, contents: nil)
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = try FileHandle(forWritingTo: errFile)
    p.standardInput = FileHandle.nullDevice
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        let err = (try? String(contentsOf: errFile, encoding: .utf8)) ?? ""
        throw Failure(description: "\(args[0]) exited \(p.terminationStatus): \(err.suffix(500))")
    }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - App

func screenshotDir() -> URL {
    let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    return URL(fileURLWithPath: ((loc ?? "~/Desktop") as NSString).expandingTildeInPath)
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var item: NSStatusItem!
    var src: DispatchSourceFileSystemObject?
    var seen = Set<String>()
    var windows: [NSWindow] = []
    let dir = screenshotDir()

    func applicationDidFinishLaunching(_: Notification) {
        // Edit menu so ⌘C/⌘V/⌘A work in text fields.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Vocume")
        let m = NSMenu()
        m.addItem(withTitle: "Watching \(dir.lastPathComponent) + clipboard", action: nil, keyEquivalent: "")
        m.addItem(withTitle: "Open Image…", action: #selector(pick), keyEquivalent: "o").target = self
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m

        seen = Set(images())
        src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(dir.path, O_EVTONLY), eventMask: .write, queue: .main)
        src?.setEventHandler { [weak self] in self?.scan() }
        src?.resume()

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkClipboard() }
    }

    // Screenshots set to "Clipboard" never hit disk, so poll the pasteboard too.
    // ponytail: any newly copied image opens (screenshots carry no marker); add a menu toggle if that gets annoying.
    var pbCount = NSPasteboard.general.changeCount
    func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != pbCount else { return }
        pbCount = pb.changeCount
        guard pb.types?.contains(ownType) != true,
              let png = pb.data(forType: .png)
                ?? pb.data(forType: .tiff).flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clipboard-\(Int(Date().timeIntervalSince1970)).png")
        if (try? png.write(to: url)) != nil { show(url) }
    }

    // ponytail: any new png in the folder opens; filter by name if that gets noisy (name is localized, e.g. "Bildschirmfoto").
    func images() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") && !$0.hasPrefix(".") }
    }

    func scan() {
        for f in images() where !seen.contains(f) {
            seen.insert(f)
            if !ownFiles.contains(f) { show(dir.appendingPathComponent(f)) }
        }
    }

    func show(_ url: URL) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        let model = Model(url: url)
        model.window = w
        w.title = url.lastPathComponent
        w.contentView = NSHostingView(rootView: EditorView(m: model))
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ n: Notification) { windows.removeAll { $0 === n.object as? NSWindow } }

    @objc func pick() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg]
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { show(u) }
    }
}

// Renders marks onto an image to eyeball drawing without the UI. The optional arg is either a JSON
// AI reply (tests OCR matching without an LLM) or a request sent to `claude` (tests the real thing).
@MainActor func demo(_ input: String, _ output: String, _ arg: String?) {
    let m = Model(url: URL(fileURLWithPath: input))
    if let arg {
        let texts = ocr(m.url)
        let claude = arg.hasPrefix("[") ? nil : WarmClaude()
        if claude != nil { Thread.sleep(forTimeInterval: 3) }  // like the app: warm before you hit Annotate
        let t = Date()
        let marks = arg.hasPrefix("[")
            ? try! JSONDecoder().decode([Mark].self, from: Data(arg.utf8))
            : try! runAI(aiPrompt(arg, texts), m.url, claude: claude)
        print(String(format: "AI took %.1fs", Date().timeIntervalSince(t)))
        print(marks.map { "\($0.type) \($0.match ?? "@\($0.x),\($0.y)") \($0.color ?? "")" })
        m.marks = resolve(marks, texts, Pixels(m.url)!)
        print("\(m.marks.count) marks")
    } else { m.marks = [
        Mark(type: "arrow", x: 0.08, y: 0.12, w: 0.22, h: 0.18, label: "Look here"),
        Mark(type: "box", x: 0.35, y: 0.15, w: 0.3, h: 0.25, label: "Broken layout", color: "blue"),
        Mark(type: "highlight", x: 0.1, y: 0.55, w: 0.35, h: 0.06, color: "yellow"),
        Mark(type: "redact", x: 0.55, y: 0.55, w: 0.25, h: 0.06, color: "black"),
        Mark(type: "pen", x: 0.7, y: 0.75, color: "green",
             points: (0..<40).map { CGPoint(x: 0.7 + Double($0) * 0.005, y: 0.8 + sin(Double($0) / 4) * 0.04) }),
        Mark(type: "text", x: 0.1, y: 0.75, label: "Plain text note", color: "purple"),
        Mark(type: "step", x: 0.75, y: 0.2, color: "orange"),
        Mark(type: "step", x: 0.85, y: 0.3, label: "then this", color: "orange", size: 1.6),
    ] }
    guard let png = m.rendered() else { fatalError("render failed") }
    try! png.write(to: URL(fileURLWithPath: output))
}

@main enum Vocume {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 4, args[1] == "--demo" {
            MainActor.assumeIsolated { demo(args[2], args[3], args.count > 4 ? args[4] : nil) }
            return
        }
        if args.count == 3, args[1] == "--overlay" {
            MainActor.assumeIsolated {
                func bar(_ dark: Bool, _ ago: Double) -> some View {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(.purple).imageScale(.large)
                        Text("Claude").padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        ThinkingOverlay(stage: "Claude is annotating", since: Date().addingTimeInterval(-ago)).frame(height: 28)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(width: 760)
                    .background(dark ? Color(white: 0.17) : Color(white: 0.95))
                    .environment(\.colorScheme, dark ? .dark : .light)
                }
                let r = ImageRenderer(content: VStack(spacing: 0) { bar(false, 0.7); bar(false, 1.4); bar(true, 0.7); bar(true, 1.4) })
                r.scale = 2
                try! NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
            }
            return
        }
        signal(SIGPIPE, SIG_IGN)  // a CLI exiting mid-write should be an error, not a crash
        let app = NSApplication.shared
        let d = Delegate()
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
