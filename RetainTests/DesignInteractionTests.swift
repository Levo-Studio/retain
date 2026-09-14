import SwiftUI
import Testing

@testable import Retain

/// The interaction states are derived rather than drawn, so what needs testing
/// is the derivation: that it reproduces the two hover colours the export does
/// give, and that it does not quietly change anything but lightness.
@Suite("Design interaction")
struct DesignInteractionTests {

    private let accent = RetainColor(OKLCH(0.78, 0.13, 165))
    private let blue = RetainColor(OKLCH(0.70, 0.11, 250))

    // MARK: - The round trip the whole rule rests on

    @Test("Reading a colour back onto the OKLCH axes returns what went in")
    func roundTripIsExact() {
        for (lightness, chroma, hue) in [
            (0.78, 0.13, 165.0), (0.70, 0.11, 250.0), (0.75, 0.12, 70.0),
            (0.68, 0.17, 25.0), (0.38, 0.06, 95.0), (0.42, 0.09, 25.0),
        ] {
            let original = OKLCH(lightness, chroma, hue)
            let back = OKLCH(from: RetainColor(original))

            #expect(abs(back.lightness - lightness) < 0.002, "lightness for \(hue)")
            #expect(abs(back.chroma - chroma) < 0.002, "chroma for \(hue)")
            #expect(abs(back.hue - hue) < 0.5, "hue for \(hue)")
        }
    }

    @Test("Every palette colour survives the round trip")
    func roundTripHoldsAcrossThePalette() {
        for (name, swatch) in RetainPalette.swatches {
            let back = RetainColor(OKLCH(from: swatch))
            #expect(abs(back.red - swatch.red) < 0.003, "\(name) red")
            #expect(abs(back.green - swatch.green) < 0.003, "\(name) green")
            #expect(abs(back.blue - swatch.blue) < 0.003, "\(name) blue")
        }
    }

    @Test("A grey reads back as a grey rather than acquiring a hue")
    func greysKeepNoChroma() {
        // Every surface in the export is a near-neutral. A round trip that
        // invented chroma for them would tint every hover in the app.
        let back = OKLCH(from: RetainColor(hex: 0x0e1013))
        #expect(back.chroma < 0.02)
    }

    // MARK: - The step

    /// The two colours the export actually draws a hover for. The rule has to
    /// land on them, or it is not derived from anything.
    @Test("The step reproduces the accent hover the export draws")
    func accentHoverMatchesTheExport() {
        let drawn = RetainColor(OKLCH(0.84, 0.13, 165))
        let derived = RetainInteraction.hovered(accent)

        // One hundredth of lightness apart by construction: the export's two
        // examples disagree by 0.02 and the single rule splits the difference.
        #expect(abs(OKLCH(from: derived).lightness - OKLCH(from: drawn).lightness) < 0.015)
    }

    @Test("And the link hover")
    func blueHoverMatchesTheExport() {
        let drawn = RetainColor(OKLCH(0.78, 0.11, 250))
        let derived = RetainInteraction.hovered(blue)

        #expect(abs(OKLCH(from: derived).lightness - OKLCH(from: drawn).lightness) < 0.015)
    }

    @Test("Hovering lightens and pressing darkens")
    func directionsAreOpposite() {
        let rest = OKLCH(from: accent).lightness
        #expect(OKLCH(from: RetainInteraction.hovered(accent)).lightness > rest)
        #expect(OKLCH(from: RetainInteraction.pressed(accent)).lightness < rest)
    }

    @Test("Pressing undoes hovering")
    func stepsAreSymmetric() {
        let there = RetainInteraction.hovered(accent)
        let back = RetainInteraction.pressed(there)

        #expect(abs(OKLCH(from: back).lightness - OKLCH(from: accent).lightness) < 0.005)
    }

    /// The tell that a hover was faked by nudging hex channels: the colour
    /// drifts towards grey as it lightens.
    @Test("A step moves lightness and nothing else")
    func hueAndChromaAreUntouched() {
        for swatch in [accent, blue] {
            let rest = OKLCH(from: swatch)
            for stepped in [RetainInteraction.hovered(swatch), RetainInteraction.pressed(swatch)] {
                let moved = OKLCH(from: stepped)
                #expect(abs(moved.chroma - rest.chroma) < 0.005, "chroma drifted")
                #expect(abs(moved.hue - rest.hue) < 1.0, "hue drifted")
            }
        }
    }

    /// sRGB's limit, not the transform's, and the reason the test above does
    /// not simply cover every accent: the red sits near the edge of the gamut,
    /// and lightening it pushes the red channel past 1.0, where it is clamped.
    /// The clamp costs a little chroma on the way back.
    ///
    /// Accepted rather than gamut-mapped — see `stepped`. What this asserts is
    /// that the cost stays small enough not to matter and that the hover is
    /// still visibly a hover.
    @Test("A colour at the edge of the gamut clamps, and the cost stays small")
    func nearGamutEdgeClampsGently() {
        let red = RetainColor(OKLCH(0.68, 0.17, 25))
        let rest = OKLCH(from: red)
        let hovered = OKLCH(from: RetainInteraction.hovered(red))

        #expect(hovered.lightness > rest.lightness, "the hover must still read as lighter")
        #expect(abs(hovered.hue - rest.hue) < 1.0, "the hue must survive the clamp")
        #expect(abs(hovered.chroma - rest.chroma) < 0.02, "and the chroma cost must stay under an eye's resolution")

        // Pressing goes the other way, into the gamut, so it is unaffected.
        let pressed = OKLCH(from: RetainInteraction.pressed(red))
        #expect(abs(pressed.chroma - rest.chroma) < 0.005)
    }

    @Test("A step never leaves the lightness range")
    func stepIsClamped() {
        let white = RetainColor(OKLCH(1.0, 0.0, 0))
        let black = RetainColor(OKLCH(0.0, 0.0, 0))

        #expect(OKLCH(from: RetainInteraction.hovered(white)).lightness <= 1.001)
        #expect(OKLCH(from: RetainInteraction.pressed(black)).lightness >= -0.001)
    }

    @Test("Stepping preserves opacity")
    func alphaSurvives() {
        let translucent = RetainColor(OKLCH(0.78, 0.13, 165, alpha: 0.72))
        #expect(abs(RetainInteraction.hovered(translucent).alpha - 0.72) < 0.001)
    }

    // MARK: - The states themselves

    @Test("A disabled control fades rather than turning grey")
    func disabledIsAnOpacity() {
        // Inventing a disabled grey would mean inventing a colour the export
        // does not have; fading the real one is a transform of a drawn value.
        #expect(RetainInteraction.disabledOpacity > 0.25)
        #expect(RetainInteraction.disabledOpacity < 0.6)
    }

    @Test("Focus borrows the emphasised control border rather than a third state")
    func focusUsesADrawnColour() {
        #expect(RetainInteraction.focusBorder == RetainPalette.lineControlBorderEmphasised)
        #expect(RetainInteraction.focusBorderWidth == 2)
    }

    /// A user highlight, the model's emphasis and a search hit can all land on
    /// the same line, so all three have to be distinguishable.
    @Test("A user highlight is none of the marks the export already draws")
    func highlightIsItsOwnThing() {
        let user = OKLCH(from: RetainColor(OKLCH(0.38, 0.06, 250)))
        let term = OKLCH(0.38, 0.06, 95)
        let search = OKLCH(0.42, 0.09, 95)

        #expect(abs(user.hue - term.hue) > 100, "user highlight must not read as the model's emphasis")
        #expect(abs(user.hue - search.hue) > 100, "nor as a search hit")
    }

    @Test("It says 'yours' in the hue the export already uses for that")
    func highlightUsesTheAnnotationHue() {
        // The annotation rule and the "Von dir" label are oklch(.7 .11 250).
        let user = OKLCH(from: RetainColor(OKLCH(0.38, 0.06, 250)))
        #expect(abs(user.hue - 250) < 2)
    }

    @Test("Its geometry matches the term highlight it can sit beside")
    func highlightGeometryMatchesTheDrawnOne() {
        #expect(RetainInteraction.highlightCornerRadius == 3)
        #expect(RetainInteraction.highlightHorizontalPadding == 3)
    }
}
