import CoreGraphics
import Testing

@testable import VocumeCore

@Suite("Mark geometry")
struct MarkGeometryTests {
    let size = CGSize(width: 1000, height: 500)

    @Test func unitScalesWithTheLongerSide() {
        #expect(Mark.unit(for: CGSize(width: 2000, height: 100)) == 2)
        #expect(Mark.unit(for: CGSize(width: 100, height: 3000)) == 3)
    }

    @Test func frameNormalizesBackwardDrags() {
        let frame = Mark(kind: .box, x: 0.5, y: 0.5, w: -0.2, h: -0.4).frame(in: size)
        let expected = CGRect(x: 300, y: 50, width: 200, height: 200)
        #expect(abs(frame.minX - expected.minX) < 1e-9 && abs(frame.minY - expected.minY) < 1e-9)
        #expect(abs(frame.width - expected.width) < 1e-9 && abs(frame.height - expected.height) < 1e-9)
    }

    @Test func textLabelHangsFromItsAnchor() {
        let mark = Mark(kind: .text, x: 0.1, y: 0.2, label: "Note")
        let pill = mark.labelRect(in: size)
        #expect(pill.origin == CGPoint(x: 100, y: 100))
        #expect(pill.width > 0 && pill.height > 0)
    }

    @Test func boundsCoverShapeAndLabel() {
        let mark = Mark(kind: .box, x: 0.2, y: 0.4, w: 0.2, h: 0.2, label: "Look")
        let bounds = mark.bounds(in: size)
        #expect(bounds.contains(mark.frame(in: size)))
        #expect(bounds.contains(mark.labelRect(in: size)))
    }

    @Test func penBoundsCoverAllPoints() {
        let mark = Mark(kind: .pen, x: 0.1, y: 0.1, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.8)])
        let bounds = mark.bounds(in: size)
        for point in mark.penPoints(in: size) { #expect(bounds.contains(point)) }
    }
}
