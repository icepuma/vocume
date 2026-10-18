import CoreGraphics
import Foundation
import ImageIO

/// A `.vocume` file: a screenshot with its marks, crop and undo/redo history, so it reopens exactly
/// as it was left, undo included. A binary property list; `image` holds the original image file.
public struct VocumeDocument: Codable, Equatable, Sendable {
    /// Marks and crop at one point in the history: what undo and redo put back.
    public struct State: Codable, Equatable, Sendable {
        public var marks: [Mark]
        public var crop: CGRect?

        public init(marks: [Mark] = [], crop: CGRect? = nil) {
            self.marks = marks
            self.crop = crop
        }

        /// A crop from a file is kept to the image, or dropped if not finite or under a millionth of
        /// it: a damaged or hostile file's crop would otherwise overflow the editor's zoom and size
        /// readouts and crash it.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            marks = try container.decode([Mark].self, forKey: .marks)
            crop = try container.decodeIfPresent(CGRect.self, forKey: .crop).flatMap { crop in
                let image = CGRect(x: 0, y: 0, width: 1, height: 1)
                guard [crop.minX, crop.minY, crop.width, crop.height].allSatisfy(\.isFinite) else { return nil }
                let kept = image.contains(crop) ? crop : crop.intersection(image)  // inside: as saved, to the bit
                return kept.width < 1e-6 || kept.height < 1e-6 ? nil : kept
            }
        }

        private enum CodingKeys: String, CodingKey {
            case marks, crop
        }
    }

    public static let fileExtension = "vocume"

    /// The image's file name ("Vocume 2026-10-18T14.03.22.png"), for titles and exports.
    public var imageName: String
    public var image: Data
    public var state = State()
    public var undo: [State] = []
    public var redo: [State] = []

    public init(imageName: String, image: Data) {
        self.imageName = imageName
        self.image = image
    }

    public init(contentsOf url: URL) throws {
        self = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Every screenshot Vocume opens, kept as a `.vocume` document the way Snagit keeps its library:
/// edits save as they happen, closing never asks, and recent captures reopen with their history.
public struct CaptureLibrary: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Documents keep what redactions cover; like the `$TMPDIR` captures, they stay out of backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try? excluded.setResourceValues(values)
    }

    /// `~/Library/Application Support/Vocume/Captures`.
    public static let shared = CaptureLibrary(
        folder: .applicationSupportDirectory.appending(path: "Vocume/Captures", directoryHint: .isDirectory))

    /// Opens `file` for editing: a `.vocume` document as it is, or an image as a new document in the
    /// library. `image` is a plain image file for OCR and the AI, written out of a document.
    public func open(_ file: URL) throws -> (document: VocumeDocument, url: URL, image: URL) {
        let unreadable = CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: file])
        guard file.pathExtension.lowercased() == VocumeDocument.fileExtension else {
            let document = VocumeDocument(imageName: file.lastPathComponent, image: try Data(contentsOf: file))
            guard Self.isImage(document.image) else { throw unreadable }
            let url = newFile(named: file.deletingPathExtension().lastPathComponent)
            try document.write(to: url)
            return (document, url, file)
        }
        let document = try VocumeDocument(contentsOf: file)
        guard Self.isImage(document.image) else { throw unreadable }
        // The name comes from the file, which may come from anyone: never let it leave the folder.
        let name = (document.imageName as NSString).lastPathComponent
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appending(
            path: name.isEmpty || name.hasPrefix(".") || name.contains("/") ? "Screenshot.png" : name)
        try document.image.write(to: image)
        return (document, file, image)
    }

    /// Documents, most recently changed first.
    public func recent() -> [URL] {
        documents().sorted { $0.modified > $1.modified }.map(\.url)
    }

    /// Deletes documents unchanged since `cutoff`, except the `open` ones.
    public func prune(before cutoff: Date, keeping open: [URL] = []) {
        let open = Set(open.map(\.standardizedFileURL.path))
        for document in documents()
        where document.modified < cutoff && !open.contains(document.url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: document.url)
        }
    }

    /// An image with a size: an editor on anything else divides by zero.
    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0
            && (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0
    }

    /// "name.vocume", or "name 2.vocume"… when taken.
    private func newFile(named name: String) -> URL {
        var url = folder.appending(path: "\(name).\(VocumeDocument.fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(name) \(number).\(VocumeDocument.fileExtension)")
            number += 1
        }
        return url
    }

    private func documents() -> [(url: URL, modified: Date)] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension.lowercased() == VocumeDocument.fileExtension }.map { url in
            (
                url,
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
            )
        }
    }
}
