import CoreGraphics
import SwiftUI
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

    @Test func handlesOnlyWhereReshapingMakesSense() {
        #expect(Mark(kind: .box, x: 0, y: 0).handles.count == 8)
        #expect(Mark(kind: .arrow, x: 0, y: 0).handles == [.topLeading, .bottomTrailing])
        for kind in [Mark.Kind.pen, .text, .step] { #expect(Mark(kind: kind, x: 0, y: 0).handles.isEmpty) }
    }

    @Test func cornerMovesTwoEdgesAndKeepsTheOppositeCorner() {
        var box = Mark(kind: .box, x: 0.2, y: 0.2, w: 0.4, h: 0.4)
        box.move(.topLeading, to: CGPoint(x: 0.1, y: 0.3))
        let corner = box.point(of: .bottomTrailing, in: CGSize(width: 1, height: 1))
        #expect(abs(corner.x - 0.6) < 1e-9 && abs(corner.y - 0.6) < 1e-9)
        #expect(box.point(of: .topLeading, in: CGSize(width: 1, height: 1)) == CGPoint(x: 0.1, y: 0.3))
    }

    @Test func edgeMovesOneSide() {
        var box = Mark(kind: .redact, x: 0.2, y: 0.2, w: 0.4, h: 0.4)
        box.move(.trailing, to: CGPoint(x: 0.9, y: 0.95))
        #expect(box.x == 0.2 && box.y == 0.2 && box.h == 0.4)
        #expect(abs((box.w ?? 0) - 0.7) < 1e-9)
    }

    @Test func draggingPastTheOppositeEdgeFlipsThenNormalizes() {
        var box = Mark(kind: .highlight, x: 0.4, y: 0.4, w: 0.2, h: 0.2)
        box.move(.leading, to: CGPoint(x: 0.8, y: 0.5))
        box.normalize()
        #expect(abs(box.x - 0.6) < 1e-9 && abs((box.w ?? 0) - 0.2) < 1e-9)
    }

    @Test func arrowEndsMoveIndependently() {
        var arrow = Mark(kind: .arrow, x: 0.5, y: 0.5, w: -0.2, h: 0.1)
        arrow.move(.topLeading, to: CGPoint(x: 0.1, y: 0.1))
        let unit = CGSize(width: 1, height: 1)
        #expect(arrow.point(of: .topLeading, in: unit) == CGPoint(x: 0.1, y: 0.1))
        let tip = arrow.point(of: .bottomTrailing, in: unit)
        #expect(abs(tip.x - 0.3) < 1e-9 && abs(tip.y - 0.6) < 1e-9)
        arrow.normalize()  // arrows keep their direction
        #expect(arrow.x == 0.1 && arrow.y == 0.1)
    }
}
