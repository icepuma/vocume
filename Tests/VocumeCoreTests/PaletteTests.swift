import AppKit
import SwiftUI
import Testing

@testable import VocumeCore

@Suite("Palette")
struct PaletteTests {
    @Test func customColoursRoundTripAsHex() {
        let hex = Palette.name(for: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        #expect(hex == "#336699")
        let color = NSColor(Palette.color(named: hex)).usingColorSpace(.sRGB)
        #expect(abs((color?.redComponent ?? 0) - 0.2) < 0.01 && abs((color?.blueComponent ?? 0) - 0.6) < 0.01)
    }

    @Test func labelInkContrastsWithCustomColours() {
        #expect(Palette.ink(on: "#F5F5DC") == .black)  // beige
        #expect(Palette.ink(on: "#14213D") == .white)  // navy
        #expect(Palette.ink(on: "yellow") == .black)
        #expect(Palette.ink(on: "red") == .white)
    }

    @Test func malformedNamesFallBackToRed() {
        for name in ["#12345", "#GGGGGG", "teal", ""] {
            #expect(Palette.color(named: name) == Palette.color(named: "red"))
        }
    }
}
