import Foundation
import Testing

@testable import VocumeCore

@Suite("Mark decoding")
struct MarkDecodingTests {
    private func decode(_ json: String) throws -> [Mark] {
        try JSONDecoder().decode([Mark].self, from: Data(json.utf8))
    }

    @Test func matchMarksNeedNoPosition() throws {
        let marks = try decode(#"[{"type":"redact","match":"o","color":"white","word":true}]"#)
        #expect(marks.count == 1)
        #expect(marks[0].kind == .redact)
        #expect(marks[0].match == "o")
        #expect(marks[0].word == true)
        #expect(marks[0].x == 0 && marks[0].y == 0)
    }

    @Test func unknownTypeFallsBackToBox() throws {
        let marks = try decode(#"[{"type":"circle","x":0.1,"y":0.2,"w":0.3,"h":0.4}]"#)
        #expect(marks[0].kind == .box)
        #expect(marks[0].w == 0.3)
    }

    @Test func penPointsDecodeFromPairs() throws {
        let marks = try decode(#"[{"type":"pen","x":0,"y":0,"points":[[0.1,0.2],[0.3,0.4]]}]"#)
        #expect(marks[0].points == [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)])
    }

    @Test func encodesKindAsType() throws {
        let data = try JSONEncoder().encode(Mark(kind: .step, x: 0.5, y: 0.5))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "step")
        #expect(object["kind"] == nil)
    }

    @Test func emptyTextIsDetected() {
        #expect(Mark(kind: .text, x: 0, y: 0, label: "").isEmptyText)
        #expect(!Mark(kind: .text, x: 0, y: 0, label: "hi").isEmptyText)
        #expect(!Mark(kind: .box, x: 0, y: 0).isEmptyText)
    }
}
