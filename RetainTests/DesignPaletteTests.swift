import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Retain

@Suite("Palette")
struct RetainPaletteTests {

    /// Every `oklch()` in the export that covers enough pixels in
    /// `docs/design/screens/*.png` to be read back out of the render, against
    /// the hex the browser actually painted there.
    ///
    /// This is the check that matters. The conversion could be self-consistent
    /// and still wrong; these numbers were not computed by the same code they
    /// test, they were sampled from the boards the designer looked at.
    ///
    /// The four `oklch()` tokens missing from this table — accent hover, accent
    /// 4, amber ink and the recording red — are drawn only as hairlines, as
    /// 3×4px bars, or mid-pulse, so the render has no flat area of them to
    /// sample.
    @Test("The oklch tokens match the pixels the export's own renders paint")
    func oklchMatchesTheRenderedBoards() {
        let expected: [String: String] = [
            "accent": "#56d1a3",
            "accentStep2": "#3ca17b",
            "accentStep3": "#2f7258",
            "blue": "#67a3e0",
            "amber": "#dea052",
            "redInk": "#fa8880",
            "redInkBright": "#ff9189",
            "redBorder": "#773733",
            "redError": "#f97770",
            "purple": "#b484bf",
            "termHighlight": "#4c4219",
            "searchHit": "#5d4c00",
        ]

        for (name, hex) in expected {
            let swatch = RetainPalette.swatches.first { $0.name == name }
            #expect(swatch != nil, "no swatch named \(name)")
            #expect(swatch?.colour.hexDescription == hex, "\(name)")
        }
    }

    /// The hex tokens are typed by hand out of a table, so they are checked the
    /// same way any transcribed number is: against the table.
    @Test("The hex tokens are the hex the README writes")
    func hexTokensAreTranscribedCorrectly() {
        let expected: [String: String] = [
            "surfaceCanvas": "#08090b",
            "surfaceWindow": "#0e1013",
            "surfaceTitleBar": "#16181c",
            "surfaceMetaStrip": "#14161a",
            "surfaceRail": "#131519",
            "surfaceInsetControl": "#171a1e",
            "surfaceSelectedRow": "#1b1f24",
            "surfaceChatBubble": "#1f242a",
            "surfaceHotkeyChip": "#131519",
            "lineWindowBorder": "#23272d",
            "lineDivider": "#24282e",
            "lineControlBorder": "#272b31",
            "lineControlBorderEmphasised": "#2f353c",
            "lineTableRowSeparator": "#1c2025",
            "lineTrafficLight": "#30353c",
            "inkPrimary": "#edeff2",
            "inkBodyStrong": "#e2e5e9",
            "inkBody": "#b8bec6",
            "inkMuted": "#9aa1a9",
            "inkDim": "#8e959e",
            "inkLabel": "#7c838c",
            "inkFaint": "#767d86",
            "inkFaintest": "#5d646d",
            "inkDisabled": "#3f454c",
            "onAccent": "#0b0f0d",
            "searchHitInk": "#ffffff",
        ]

        for (name, hex) in expected {
            let swatch = RetainPalette.swatches.first { $0.name == name }
            #expect(swatch?.colour.hexDescription == hex, "\(name)")
        }
    }

    /// Two tokens the design draws as different colours must not have become
    /// one value through a mistyped digit — a mistake that is invisible on
    /// screen precisely because both places then look consistent.
    @Test("No two tokens are the same colour by accident")
    func noAccidentalDuplicates() {
        var byColour: [RetainColor: [String]] = [:]
        for swatch in RetainPalette.swatches {
            byColour[swatch.colour, default: []].append(swatch.name)
        }

        for (_, names) in byColour where names.count > 1 {
            #expect(
                RetainPalette.intentionallyEqualSwatches.contains(Set(names)),
                "these are the same colour and the design says they are not: \(names.sorted())"
            )
        }
    }

    @Test("Every token is listed exactly once")
    func everyTokenIsListedOnce() {
        let names = RetainPalette.swatches.map(\.name)
        #expect(Set(names).count == names.count)
    }

    /// The four course colours are stored by index, so their order is part of
    /// the data and not a detail of the dialog.
    @Test("The course colours are accent, blue, amber, purple, in that order")
    func courseColourOrder() {
        #expect(RetainPalette.courseSwatches.count == 4)
        #expect(RetainPalette.courseSwatches[0].hexDescription == "#56d1a3")
        #expect(RetainPalette.courseSwatches[1].hexDescription == "#67a3e0")
        #expect(RetainPalette.courseSwatches[2].hexDescription == "#dea052")
        #expect(RetainPalette.courseSwatches[3].hexDescription == "#b484bf")
    }

    /// The `Color` handed to a view has to be the swatch it is named after.
    /// Nothing else in the file checks that the two lists were kept in step.
    @Test("The exposed colours resolve to the swatches they are named after")
    @MainActor
    func exposedColoursResolveToTheirSwatch() {
        let pairs: [(Color, String)] = [
            (RetainPalette.surfaceWindow, "surfaceWindow"),
            (RetainPalette.inkPrimary, "inkPrimary"),
            (RetainPalette.accent, "accent"),
            (RetainPalette.termHighlight, "termHighlight"),
            (RetainPalette.redBorder, "redBorder"),
            (RetainPalette.waveformBarPaused, "waveformBarPaused"),
        ]

        for (colour, name) in pairs {
            let swatch = RetainPalette.swatches.first { $0.name == name }
            #expect(resolved(colour) == swatch?.colour.hexDescription, "\(name)")
        }
    }

    @MainActor
    private func resolved(_ colour: Color) -> String? {
        guard let sRGB = NSColor(colour).usingColorSpace(.sRGB) else { return nil }
        return RetainColor(
            red: Double(sRGB.redComponent),
            green: Double(sRGB.greenComponent),
            blue: Double(sRGB.blueComponent),
            alpha: Double(sRGB.alphaComponent)
        ).hexDescription
    }
}
