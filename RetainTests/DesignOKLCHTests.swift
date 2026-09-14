import Foundation
import Testing

@testable import Retain

@Suite("Oklch conversion")
struct OKLCHTests {

    /// The anchors of the colour space. If the matrices or the transfer
    /// function are wrong anywhere, at least one of these moves.
    ///
    /// The Oklch coordinates of the sRGB primaries are the ones CSS Color 4
    /// publishes; a browser round-trips `#ff0000` to and from exactly these.
    @Test("The sRGB primaries come back out as themselves")
    func primaries() {
        #expect(OKLCH(0.62795537, 0.25768330, 29.2338851).hexDescription == "#ff0000")
        #expect(OKLCH(0.86644238, 0.29482680, 142.4953480).hexDescription == "#00ff00")
        #expect(OKLCH(0.45201371, 0.31321437, 264.0520206).hexDescription == "#0000ff")
    }

    @Test("Black, white and a mid grey")
    func achromatic() {
        #expect(OKLCH(0, 0, 0).hexDescription == "#000000")
        #expect(OKLCH(1, 0, 0).hexDescription == "#ffffff")
        #expect(OKLCH(0.59987, 0, 0).hexDescription == "#808080")
    }

    /// Chroma zero is grey at every hue — a conversion that leaks a hue angle
    /// into an achromatic colour would fail here and nowhere else.
    @Test("Hue does not matter at zero chroma")
    func hueIrrelevantWithoutChroma() {
        let grey = OKLCH(0.7, 0, 0).hexDescription
        for hue in stride(from: 0.0, to: 360.0, by: 37.0) {
            #expect(OKLCH(0.7, 0, hue).hexDescription == grey)
        }
    }

    @Test("Lightness is monotonic")
    func lightnessIsMonotonic() {
        var previous = -1.0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let green = OKLCH(step, 0.05, 165).sRGB.green
            #expect(green > previous)
            previous = green
        }
    }

    /// An out-of-gamut request is clipped rather than wrapped: a channel that
    /// came back negative must not reappear as a bright one.
    @Test("Out of gamut clips instead of wrapping")
    func outOfGamutClips() {
        let impossible = RetainColor(OKLCH(0.9, 0.4, 145))
        #expect(impossible.red >= 0 && impossible.red <= 1)
        #expect(impossible.green >= 0 && impossible.green <= 1)
        #expect(impossible.blue >= 0 && impossible.blue <= 1)
    }
}
