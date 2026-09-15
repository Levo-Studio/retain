import SwiftUI

/// Every colour in `docs/design/`, and nothing else.
///
/// The names are the names the design README gives — surfaces, lines, ink,
/// accents — so that a value can be traced from a call site back to the row of
/// the table it came from without guessing. Where the README and
/// `Retain - Alle Screens.dc.html` disagree the HTML wins, because it is what
/// was drawn; where the HTML paints something the README's tables do not name,
/// it is still a colour the app needs, and it is here with a note saying so.
///
/// **Dark only.** The export has no light board, so there is no light
/// appearance to build and no system material is used anywhere: every surface
/// is painted explicitly, because a material borrows an appearance that was
/// never designed and changes with whatever is behind the window.
nonisolated enum RetainPalette {

    // MARK: - Surfaces

    /// The board background behind the window. Not an app surface — it is here
    /// because previews and screenshots need the same ground the export used.
    static var surfaceCanvas: Color { canvas.color }

    /// Window body, popover body, dialog body.
    static var surfaceWindow: Color { window.color }

    static var surfaceTitleBar: Color { titleBar.color }

    /// The header strip under the title bar; the popover header; the current
    /// row in the library table.
    static var surfaceMetaStrip: Color { metaStrip.color }

    /// Transcript rail, chapters/chat rail, library sidebar, settings sidebar.
    static var surfaceRail: Color { rail.color }

    /// Text fields, search fields, secondary buttons, cards, composer.
    static var surfaceInsetControl: Color { insetControl.color }

    /// Sidebar selection, active segment.
    static var surfaceSelectedRow: Color { selectedRow.color }

    /// User messages in the chat rail.
    static var surfaceChatBubble: Color { chatBubble.color }

    /// The `⌘⇧M · 2 markers` chip inside the annotation bar. The same value as
    /// the rail, deliberately — the export writes `#131519` in both places.
    static var surfaceHotkeyChip: Color { hotkeyChip.color }

    // MARK: - Lines

    /// Window, popover and dialog outline; also the progress track.
    static var lineWindowBorder: Color { windowBorder.color }

    /// Title-bar bottom, strip bottom, rail edges, tab-bar bottom, dialog
    /// header.
    static var lineDivider: Color { divider.color }

    /// Fields, secondary buttons, cards, composer.
    static var lineControlBorder: Color { controlBorder.color }

    /// A field with content or focus, and the "Pause" outline in the recording
    /// panel.
    static var lineControlBorderEmphasised: Color { controlBorderEmphasised.color }

    static var lineTableRowSeparator: Color { tableRowSeparator.color }

    /// The three 10px circles in the title bar.
    static var lineTrafficLight: Color { trafficLight.color }

    /// The outline of a chat source chip. Drawn on board 04 and not named in
    /// the README's line table.
    static var lineChipBorder: Color { chipBorder.color }

    // MARK: - Ink

    /// Headings, values, active text.
    static var inkPrimary: Color { primary.color }

    /// Annotation body, latest transcript line, table lesson titles.
    static var inkBodyStrong: Color { bodyStrong.color }

    /// Paragraphs, transcript body, secondary buttons, field labels.
    static var inkBody: Color { body.color }

    /// Bullet lists, and the timestamp of the newest transcript line.
    static var inkMuted: Color { muted.color }

    /// Title-bar subtitle, settings descriptions, paused values, the block
    /// being written.
    static var inkDim: Color { dim.color }

    /// Uppercase labels, captions, chevrons, placeholders.
    static var inkLabel: Color { label.color }

    /// The word "live" in the transcript rail header.
    static var inkFaint: Color { faint.color }

    /// Note block numbers; the typing dots.
    static var inkFaintest: Color { faintest.color }

    /// The block number of the block still being written.
    static var inkDisabled: Color { disabled.color }

    // MARK: - Accents

    /// Primary buttons, active tab underline, connected state, progress fill,
    /// meter peak, current course rail.
    static var accent: Color { accentBase.color }

    /// Primary button hover.
    static var accentHover: Color { accentHoverValue.color }

    /// Meter, second ring.
    static var accentStep2: Color { accent2.color }

    /// Meter, third ring.
    static var accentStep3: Color { accent3.color }

    /// Meter, outermost ring.
    static var accentStep4: Color { accent4.color }

    /// Text and glyphs on an accent fill.
    static var onAccent: Color { onAccentValue.color }

    /// The second line inside the accent-filled "open summary" card, which the
    /// export writes as `rgba(11,15,13,.72)` — the on-accent ink at 72 %.
    static var onAccentSecondary: Color { onAccentSecondaryValue.color }

    /// Annotation rule and label, chat source chips, links, course colour 2.
    static var blue: Color { blueValue.color }

    /// Link hover.
    static var blueHover: Color { blueHoverValue.color }

    /// Left rule, marker dots, the status dot while summarizing, course
    /// colour 3.
    static var amber: Color { amberValue.color }

    /// The timestamp and label of an audience line or a marker.
    static var amberInk: Color { amberInkValue.color }

    /// The recording dot and the text caret.
    static var redRecording: Color { red.color }

    /// The "Recording" label, destructive button text, the "recording" status
    /// in the library table.
    static var redInk: Color { redInkValue.color }

    /// Destructive button text in the popover, which is a step brighter than
    /// the same text in a window.
    static var redInkBright: Color { redInkBrightValue.color }

    /// Destructive button outline.
    static var redBorder: Color { redBorderValue.color }

    /// The dot in the "No connection" dialog.
    static var redError: Color { redErrorValue.color }

    /// Course colour 4.
    static var purple: Color { purpleValue.color }

    /// The background behind an emphasised term in the notes.
    static var termHighlight: Color { termHighlightValue.color }

    /// A match highlight in the transcript.
    static var searchHit: Color { searchHitValue.color }

    /// The ink on a search hit, which is plain white and not the primary ink.
    static var searchHitInk: Color { searchHitInkValue.color }

    // MARK: - Waveform

    // The level meter's inactive bars. Drawn on board 02 and not named in the
    // README's colour tables, which stop at the accent ramp the active bars
    // use.

    /// A bar that has already passed.
    static var waveformBarIdle: Color { waveformIdle.color }

    /// The one bar between the idle grey and the accent ramp.
    static var waveformBarRecent: Color { waveformRecent.color }

    /// Every bar while the recording is paused.
    static var waveformBarPaused: Color { waveformPaused.color }

    // MARK: - Course colours

    /// The four colours a course can have, in the order the new-course dialog
    /// offers them. Stored by index, which is why the order is part of the API
    /// and not an implementation detail.
    static var courseColours: [Color] { courseSwatches.map(\.color) }

    static let courseSwatches: [RetainColor] = [accentBase, blueValue, amberValue, purpleValue]

    // MARK: - Colours as values

    // On the OKLCH axes rather than as a SwiftUI `Color`, because
    // `RetainInteraction` steps lightness for hover and pressed and lightness
    // cannot be read back out of a `Color`. Only the tokens a control is
    // actually drawn with are here; everything else is read as a colour, and
    // the `Color` accessors above are what a view uses at rest.

    /// The outline of "Stop" and "Finish".
    static var redBorderSwatch: RetainColor { redBorderValue }

    /// The outline of "Pause" in the recording window's rail, which the export
    /// draws a step stronger than every other control border.
    static var controlBorderEmphasisedSwatch: RetainColor { controlBorderEmphasised }

    /// The surfaces a control sits on: a field and a secondary button, a
    /// selected sidebar row or segment, and the strip a table's current row is
    /// filled with.
    static var insetControlSwatch: RetainColor { insetControl }
    static var selectedRowSwatch: RetainColor { selectedRow }
    static var metaStripSwatch: RetainColor { metaStrip }

    // MARK: - Values

    private static let canvas = RetainColor(hex: 0x08090B)
    private static let window = RetainColor(hex: 0x0E1013)

    // **The export draws these two a shade lighter than the window and the
    // owner asked for them to stop.** Four near-identical greys stacked down a
    // window read as banding rather than as structure: the title strip looked
    // like a bar bolted on top of the page instead of part of it. The dividers
    // already say where one band ends and the next begins, and they say it
    // without changing the colour of the paper.
    //
    // This is a deliberate departure from `docs/design/`, made on the owner's
    // word. The tokens stay — every view still asks for the surface it means,
    // so putting the shades back is one line each.
    private static let titleBar = window
    private static let metaStrip = window
    private static let rail = RetainColor(hex: 0x131519)
    private static let insetControl = RetainColor(hex: 0x171A1E)
    private static let selectedRow = RetainColor(hex: 0x1B1F24)
    private static let chatBubble = RetainColor(hex: 0x1F242A)
    private static let hotkeyChip = RetainColor(hex: 0x131519)

    private static let windowBorder = RetainColor(hex: 0x23272D)
    private static let divider = RetainColor(hex: 0x24282E)
    private static let controlBorder = RetainColor(hex: 0x272B31)
    private static let controlBorderEmphasised = RetainColor(hex: 0x2F353C)
    private static let tableRowSeparator = RetainColor(hex: 0x1C2025)
    private static let trafficLight = RetainColor(hex: 0x30353C)
    private static let chipBorder = RetainColor(hex: 0x2A3038)

    private static let primary = RetainColor(hex: 0xEDEFF2)
    private static let bodyStrong = RetainColor(hex: 0xE2E5E9)
    private static let body = RetainColor(hex: 0xB8BEC6)
    private static let muted = RetainColor(hex: 0x9AA1A9)
    private static let dim = RetainColor(hex: 0x8E959E)
    private static let label = RetainColor(hex: 0x7C838C)
    private static let faint = RetainColor(hex: 0x767D86)
    private static let faintest = RetainColor(hex: 0x5D646D)
    private static let disabled = RetainColor(hex: 0x3F454C)

    private static let accentBase = RetainColor(OKLCH(0.78, 0.13, 165))
    private static let accentHoverValue = RetainColor(OKLCH(0.84, 0.13, 165))
    private static let accent2 = RetainColor(OKLCH(0.64, 0.11, 165))
    private static let accent3 = RetainColor(OKLCH(0.50, 0.08, 165))
    private static let accent4 = RetainColor(OKLCH(0.42, 0.06, 165))
    private static let onAccentValue = RetainColor(hex: 0x0B0F0D)
    private static let onAccentSecondaryValue = RetainColor(hex: 0x0B0F0D, alpha: 0.72)
    private static let blueValue = RetainColor(OKLCH(0.70, 0.11, 250))
    private static let blueHoverValue = RetainColor(OKLCH(0.78, 0.11, 250))
    private static let amberValue = RetainColor(OKLCH(0.75, 0.12, 70))
    private static let amberInkValue = RetainColor(OKLCH(0.78, 0.11, 70))
    private static let red = RetainColor(OKLCH(0.68, 0.17, 25))
    private static let redInkValue = RetainColor(OKLCH(0.75, 0.14, 25))
    private static let redInkBrightValue = RetainColor(OKLCH(0.78, 0.14, 25))
    private static let redBorderValue = RetainColor(OKLCH(0.42, 0.09, 25))
    private static let redErrorValue = RetainColor(OKLCH(0.72, 0.16, 25))
    private static let purpleValue = RetainColor(OKLCH(0.68, 0.10, 320))
    private static let termHighlightValue = RetainColor(OKLCH(0.38, 0.06, 95))
    private static let searchHitValue = RetainColor(OKLCH(0.42, 0.09, 95))
    private static let searchHitInkValue = RetainColor(hex: 0xFFFFFF)

    private static let waveformIdle = RetainColor(hex: 0x2E343B)
    private static let waveformRecent = RetainColor(hex: 0x3A4048)
    private static let waveformPaused = RetainColor(hex: 0x22272D)

    // MARK: - Every token, for tests

    /// Every token in the palette, paired with the name it is exposed under.
    ///
    /// It exists so a test can say something a reader cannot: that two tokens
    /// the design draws as different colours have not silently become the same
    /// value through a typo. Keep it in step with the properties above — a
    /// token missing from here is a token nothing checks.
    static let swatches: [(name: String, colour: RetainColor)] = [
        ("surfaceCanvas", canvas),
        ("surfaceWindow", window),
        ("surfaceTitleBar", titleBar),
        ("surfaceMetaStrip", metaStrip),
        ("surfaceRail", rail),
        ("surfaceInsetControl", insetControl),
        ("surfaceSelectedRow", selectedRow),
        ("surfaceChatBubble", chatBubble),
        ("surfaceHotkeyChip", hotkeyChip),
        ("lineWindowBorder", windowBorder),
        ("lineDivider", divider),
        ("lineControlBorder", controlBorder),
        ("lineControlBorderEmphasised", controlBorderEmphasised),
        ("lineTableRowSeparator", tableRowSeparator),
        ("lineTrafficLight", trafficLight),
        ("lineChipBorder", chipBorder),
        ("inkPrimary", primary),
        ("inkBodyStrong", bodyStrong),
        ("inkBody", body),
        ("inkMuted", muted),
        ("inkDim", dim),
        ("inkLabel", label),
        ("inkFaint", faint),
        ("inkFaintest", faintest),
        ("inkDisabled", disabled),
        ("accent", accentBase),
        ("accentHover", accentHoverValue),
        ("accentStep2", accent2),
        ("accentStep3", accent3),
        ("accentStep4", accent4),
        ("onAccent", onAccentValue),
        ("blue", blueValue),
        ("blueHover", blueHoverValue),
        ("amber", amberValue),
        ("amberInk", amberInkValue),
        ("redRecording", red),
        ("redInk", redInkValue),
        ("redInkBright", redInkBrightValue),
        ("redBorder", redBorderValue),
        ("redError", redErrorValue),
        ("purple", purpleValue),
        ("termHighlight", termHighlightValue),
        ("searchHit", searchHitValue),
        ("searchHitInk", searchHitInkValue),
        ("waveformBarIdle", waveformIdle),
        ("waveformBarRecent", waveformRecent),
        ("waveformBarPaused", waveformPaused),
    ]

    /// The one pair of names in `swatches` the export deliberately paints the
    /// same colour. Everything else being distinct is what the palette test
    /// asserts.
    static let intentionallyEqualSwatches: Set<Set<String>> = [
        ["surfaceRail", "surfaceHotkeyChip"],
        // The window's own bands. See the colours themselves for why.
        ["surfaceWindow", "surfaceTitleBar", "surfaceMetaStrip"],
    ]
}
