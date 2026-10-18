import Foundation
import Testing

@testable import VocumeCore

@Suite("Vocume documents and the capture library")
final class VocumeDocumentTests {
    private let folder = FileManager.default.temporaryDirectory
        .appending(path: "VocumeDocumentTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: folder) }

    private func png() throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/diff-chips", withExtension: "png")))
    }

    /// Marks read back get new ids (ids aren't part of the JSON shape), so compare the rest.
    private func withoutIDs(_ state: VocumeDocument.State) -> VocumeDocument.State {
        var state = state
        for index in state.marks.indices { state.marks[index].id = UUID(uuid: UUID_NULL) }
        return state
    }

    @Test func documentKeepsImageMarksCropAndHistory() throws {
        let arrow = Mark(kind: .arrow, x: 0.1, y: 0.2, w: 0.3, h: 0.4, color: "blue")
        let pen = Mark(kind: .pen, x: 0, y: 0, points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)])
        var document = VocumeDocument(imageName: "shot.png", image: Data([1, 2, 3]))
        document.state = .init(marks: [arrow, pen], crop: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        document.undo = [.init(), .init(marks: [arrow])]
        document.redo = [.init(marks: [pen, Mark(kind: .text, x: 0.5, y: 0.5, label: "Hi")])]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "shot.vocume")
        try document.write(to: url)

        let read = try VocumeDocument(contentsOf: url)
        #expect(read.imageName == "shot.png")
        #expect(read.image == Data([1, 2, 3]))
        #expect(withoutIDs(read.state) == withoutIDs(document.state))
        #expect(read.undo.map(withoutIDs) == document.undo.map(withoutIDs))
        #expect(read.redo.map(withoutIDs) == document.redo.map(withoutIDs))
    }

    @Test func cropsFromAFileStayInsideTheImage() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "crop.vocume")
        let crops: [(CGRect, CGRect?)] = [
            (CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
            (CGRect(x: 0.5, y: 0.5, width: 2, height: 2), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            (CGRect(x: 0.1, y: 0.1, width: 0, height: 0.5), nil),
            (CGRect(x: 0.1, y: 0.1, width: .infinity, height: 0.5), nil),
            (CGRect(x: .nan, y: 0.1, width: 0.5, height: 0.5), nil),
            (CGRect(x: 3, y: 3, width: 0.5, height: 0.5), nil),
            (CGRect(x: 0.1, y: 0.1, width: 1e-300, height: 0.5), nil),
        ]
        for (crop, expected) in crops {
            var document = VocumeDocument(imageName: "shot.png", image: Data())
            document.undo = [.init(crop: crop)]
            try document.write(to: url)
            #expect(try VocumeDocument(contentsOf: url).undo[0].crop == expected, "\(crop)")
        }
    }

    @Test func openingAnImageAddsANewDocumentEachTime() throws {
        let library = CaptureLibrary(folder: folder.appending(path: "Captures"))
        let image = folder.appending(path: "shot.png")
        try png().write(to: image)

        let first = try library.open(image)
        let second = try library.open(image)
        #expect(first.url.lastPathComponent == "shot.vocume")
        #expect(second.url.lastPathComponent == "shot 2.vocume")
        #expect(first.image == image)
        #expect(try VocumeDocument(contentsOf: first.url) == first.document)
        #expect(try first.document.image == png())
    }

    @Test func onlyImagesOpen() throws {
        let library = CaptureLibrary(folder: folder)
        let junk = folder.appending(path: "junk.png")
        try Data("not an image".utf8).write(to: junk)
        #expect(throws: CocoaError.self) { try library.open(junk) }

        let empty = folder.appending(path: "empty.vocume")
        try VocumeDocument(imageName: "shot.png", image: Data()).write(to: empty)
        #expect(throws: CocoaError.self) { try library.open(empty) }

        // Any case of the extension is a document, not an image to wrap in one.
        let upper = folder.appending(path: "UPPER.VOCUME")
        try VocumeDocument(imageName: "shot.png", image: png()).write(to: upper)
        #expect(try library.open(upper).url == upper)
        #expect(library.recent().map(\.lastPathComponent).contains("UPPER.VOCUME"))
    }

    @Test func openingADocumentWritesItsImageIntoAFreshTemporaryFolder() throws {
        let library = CaptureLibrary(folder: folder)
        let names = [
            ("shot.png", "shot.png"), ("../../escape.png", "escape.png"), ("..", "Screenshot.png"),
            ("", "Screenshot.png"), ("/", "Screenshot.png"),
        ]
        for (name, expected) in names {
            let url = folder.appending(path: "shot.vocume")
            try VocumeDocument(imageName: name, image: png()).write(to: url)
            let opened = try library.open(url)
            #expect(opened.url == url)
            #expect(opened.image.lastPathComponent == expected)
            #expect(
                opened.image.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
                    == FileManager.default.temporaryDirectory.standardizedFileURL.path)
            #expect(try Data(contentsOf: opened.image) == png())
        }
    }

    @Test func recentIsNewestFirstAndPruningDropsOldClosedDocumentsOnly() throws {
        let library = CaptureLibrary(folder: folder)
        let now = Date()
        for (name, days) in [("old", 40.0), ("new", 0.0), ("middle", 10.0), ("open", 50.0)] {
            let url = folder.appending(path: "\(name).vocume")
            try VocumeDocument(imageName: "\(name).png", image: Data()).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        }
        let other = folder.appending(path: "notes.txt")
        try Data().write(to: other)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: other.path)

        #expect(
            library.recent().map(\.lastPathComponent) == ["new.vocume", "middle.vocume", "old.vocume", "open.vocume"])
        library.prune(before: now.addingTimeInterval(-30 * 86400), keeping: [folder.appending(path: "open.vocume")])
        #expect(library.recent().map(\.lastPathComponent) == ["new.vocume", "middle.vocume", "open.vocume"])
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
