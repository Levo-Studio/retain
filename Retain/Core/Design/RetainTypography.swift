import AppKit
import CoreText
import SwiftUI

// MARK: - Weight

/// The four weights the export uses, spelled as CSS spells them.
///
/// They are variation-axis values, not `NSFont.Weight` constants: DM Sans ships
/// as one variable file and 500 is a real interpolation on the `wght` axis, not
/// the nearest named face. Asking for `.medium` by trait would land on whichever
/// static instance Core Text thinks is closest and quietly change every measured
/// width on the screen.
nonisolated enum RetainFontWeight: Int, Sendable, CaseIterable {
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
}

// MARK: - A style

/// One row of the design README's type table.
///
/// It carries the CSS as written — size in px, weight, line-height as a
/// multiple, tracking in em — and converts to what SwiftUI wants only at the
/// last moment, so the values in this file can be read straight against the
/// export.
nonisolated struct RetainTextStyle: Sendable, Equatable, Hashable {

    let size: CGFloat
    let weight: RetainFontWeight

    /// The CSS `line-height` multiple, or `nil` where the export writes none
    /// and the font's own line height stands.
    let lineHeight: CGFloat?

    /// CSS `letter-spacing` in em. Negative tightens.
    let tracking: CGFloat

    /// `text-transform: uppercase`.
    let uppercase: Bool

    /// `font-variant-numeric: tabular-nums` — every timer, timestamp, duration
    /// and counter in the export has it.
    let monospacedDigits: Bool

    init(
        size: CGFloat,
        weight: RetainFontWeight,
        lineHeight: CGFloat? = nil,
        tracking: CGFloat = 0,
        uppercase: Bool = false,
        monospacedDigits: Bool = false
    ) {
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.tracking = tracking
        self.uppercase = uppercase
        self.monospacedDigits = monospacedDigits
    }

    var nsFont: NSFont {
        RetainTypography.nsFont(size: size, weight: weight)
    }

    var font: Font {
        let font = Font(nsFont)
        return monospacedDigits ? font.monospacedDigit() : font
    }

    /// CSS tracking is a fraction of the font size; SwiftUI's is points.
    var trackingPoints: CGFloat { tracking * size }

    /// What `.lineSpacing()` has to add to reach the line box CSS would draw.
    ///
    /// SwiftUI adds this *between* lines on top of the font's own line height,
    /// where CSS replaces the line box outright and splits the difference above
    /// and below. The distance from one baseline to the next — the thing that
    /// makes a paragraph look like the export — comes out the same; the space
    /// above the first line does not, by half the leading.
    var lineSpacing: CGFloat {
        guard let lineHeight else { return 0 }
        return max(0, size * lineHeight - RetainTypography.naturalLineHeight(of: self))
    }
}

// MARK: - The family, and the roles it is used in

nonisolated enum RetainTypography {

    // MARK: The family

    /// The family name DM Sans registers under.
    static let familyName = "DM Sans"

    /// The PostScript name of the variable file's default instance, which is
    /// what `Retain/Resources/Fonts/DMSans-Variable.ttf` registers.
    static let postScriptName = "DMSans-9ptRegular"

    /// `wght` and `opsz` as four-character codes.
    private static let weightAxis: UInt32 = 0x7767_6874
    private static let opticalSizeAxis: UInt32 = 0x6F70_737A

    /// The optical size axis's range in this file.
    private static let opticalSizeRange: ClosedRange<Double> = 9...40

    /// Whether the bundled face actually registered.
    ///
    /// Worth asking, because failing to register is invisible: Core Text hands
    /// back a system face for an unknown name instead of nothing, the screen
    /// still draws text, and every width, line break and measured height in the
    /// design is wrong in a way no screenshot shows. A test asserts this is
    /// true of the built bundle.
    static var isDesignFontAvailable: Bool {
        guard let font = NSFont(name: postScriptName, size: 12) else { return false }
        return font.familyName == familyName
    }

    /// DM Sans at a weight, with the optical size the export would have used.
    ///
    /// The board is drawn in a browser with `font-optical-sizing` at its
    /// default, which sets `opsz` to the font size. Core Text does not do that
    /// on its own when the variation dictionary is given explicitly, so it is
    /// set here, clamped to the axis, and the glyphs come out the shape the
    /// export drew them.
    static func nsFont(size: CGFloat, weight: RetainFontWeight) -> NSFont {
        guard isDesignFontAvailable else {
            // A missing bundled font is a build problem, not a runtime
            // condition to be handled: it means the resource did not make it
            // into the bundle or `ATSApplicationFontsPath` no longer points at
            // it. Loud in development, and still legible in release.
            assertionFailure("DM Sans did not register — check ATSApplicationFontsPath and Resources/Fonts")
            return NSFont.systemFont(ofSize: size, weight: weight.systemFallback)
        }

        let opticalSize = min(max(Double(size), opticalSizeRange.lowerBound), opticalSizeRange.upperBound)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: postScriptName as CFString,
            kCTFontVariationAttribute: [
                weightAxis: weight.rawValue,
                opticalSizeAxis: opticalSize,
            ] as CFDictionary,
        ] as CFDictionary)

        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    /// Ascent plus descent plus leading — the line box the font asks for before
    /// any `line-height` is applied.
    static func naturalLineHeight(of style: RetainTextStyle) -> CGFloat {
        let font = nsFont(size: style.size, weight: style.weight)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// The width of one `ch` — the advance of the digit zero — at a style.
    ///
    /// The note paragraphs are capped at `64ch` and `70ch` in the export, which
    /// is a measure in the text's own font and not a point value that could be
    /// written down once.
    static func chWidth(of style: RetainTextStyle) -> CGFloat {
        let font = nsFont(size: style.size, weight: style.weight)
        var glyph = CTFontGetGlyphWithName(font, "zero" as CFString)
        guard glyph != 0 else { return style.size / 2 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }

    // MARK: Headings

    /// `h3` in a note block, on both the recording screen and the detail.
    static let noteHeading = RetainTextStyle(size: 22, weight: .bold, lineHeight: 1.25, tracking: -0.015)

    static let libraryCourseHeading = RetainTextStyle(size: 21, weight: .bold, tracking: -0.015)

    static let settingsSectionHeading = RetainTextStyle(size: 17, weight: .bold, tracking: -0.01)

    static let dialogTitle = RetainTextStyle(size: 17, weight: .semibold)

    static let popoverTitleReady = RetainTextStyle(size: 19, weight: .semibold, tracking: -0.01)

    static let popoverTitleSummarizing = RetainTextStyle(size: 18, weight: .semibold)

    /// The popover title while a recording is running or paused.
    static let popoverTitleRunning = RetainTextStyle(size: 16, weight: .semibold)

    // MARK: Values

    static let timerLarge = RetainTextStyle(size: 26, weight: .semibold, lineHeight: 1, monospacedDigits: true)

    /// `.val` — the value under a meta-strip label.
    static let metaValue = RetainTextStyle(size: 14.5, weight: .medium)

    /// `.lbl` — the uppercase label above it, and everywhere else a caption is
    /// set in small caps-height letters.
    static let uppercaseLabel = RetainTextStyle(
        size: 10.5,
        weight: .medium,
        tracking: 0.07,
        uppercase: true
    )

    // MARK: Notes

    static let noteParagraphRecording = RetainTextStyle(size: 15, weight: .regular, lineHeight: 1.66)

    static let noteParagraphDetail = RetainTextStyle(size: 15, weight: .regular, lineHeight: 1.7)

    static let noteBulletRecording = RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.6)

    static let noteBulletDetail = RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.68)

    /// The two-digit number beside a note heading on the recording screen.
    static let noteBlockNumber = RetainTextStyle(size: 11, weight: .medium, monospacedDigits: true)

    /// An emphasised term keeps the paragraph's size and line height and goes
    /// up one weight. Its background and padding are in `RetainMetrics`.
    static let emphasisedTermWeight = RetainFontWeight.semibold

    // MARK: Transcript

    static let transcriptLineMain = RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.65)

    static let transcriptLineRail = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.55)

    static let transcriptLinePopover = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.5)

    static let timestampRail = RetainTextStyle(size: 10.5, weight: .medium, monospacedDigits: true)

    static let timestampMain = RetainTextStyle(size: 11.5, weight: .medium, monospacedDigits: true)

    /// The body of an annotation the user typed during the lecture.
    static let annotationBody = RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.55)

    // MARK: Chat

    static let chatMessageYours = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.55)

    static let chatMessageModel = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.6)

    // MARK: Controls

    static let tab = RetainTextStyle(size: 13, weight: .medium)

    static let segment = RetainTextStyle(size: 12, weight: .medium)

    static let sidebarRow = RetainTextStyle(size: 13, weight: .medium)

    static let tableCellTitle = RetainTextStyle(size: 14, weight: .medium)

    static let tableCellOther = RetainTextStyle(size: 12.5, weight: .regular)

    static let fieldText = RetainTextStyle(size: 13, weight: .regular)

    static let fieldLabelSettings = RetainTextStyle(size: 12.5, weight: .medium)

    static let fieldLabelDialog = RetainTextStyle(size: 12.5, weight: .regular)

    static let buttonDialogPrimary = RetainTextStyle(size: 13, weight: .semibold)

    static let buttonDialogSecondary = RetainTextStyle(size: 13, weight: .medium)

    static let buttonPopoverLarge = RetainTextStyle(size: 13.5, weight: .semibold)

    static let buttonPanelFooter = RetainTextStyle(size: 12.5, weight: .medium)

    // MARK: Captions

    // The README's type table collapses these into one row — "400 · 11.5px /
    // 12px / 12.5px depending on place" — so they are named by which of the
    // three they are and not by what they sit under.

    static let captionSmall = RetainTextStyle(size: 11.5, weight: .regular)

    static let captionMedium = RetainTextStyle(size: 12, weight: .regular)

    static let captionLarge = RetainTextStyle(size: 12.5, weight: .regular)

    // MARK: - Roles the type table does not name

    // Everything below is read out of `Retain - Alle Screens.dc.html` rather
    // than the README's type table, which names the roles that repeat and
    // leaves the one-offs to the boards. They are here so that a screen has a
    // name to reach for instead of a literal.

    /// The recording's title in the title bar of the detail, library and
    /// settings windows.
    static let titleBarSubtitle = RetainTextStyle(size: 12, weight: .medium)

    /// The elapsed time in the title-bar pill.
    static let titleBarTimer = RetainTextStyle(size: 12, weight: .medium, monospacedDigits: true)

    /// "Speaker detected" and "Microphone on · 8.6 W" in the title bar.
    static let titleBarStatus = RetainTextStyle(size: 11.5, weight: .medium)

    /// The "Export" button in the title bar, and the term pill in the library.
    static let titleBarButton = RetainTextStyle(size: 11.5, weight: .medium)

    static let titleBarTermPill = RetainTextStyle(size: 12, weight: .medium)

    /// A `▾` beside a value that opens a menu.
    static let chevron = RetainTextStyle(size: 10, weight: .regular)

    /// "writing …" beside the heading of the block being written.
    static let writingLabel = RetainTextStyle(size: 11.5, weight: .medium)

    /// The right-hand note in a rail header — "live", "Speaker", a timestamp.
    static let railHeaderNote = RetainTextStyle(size: 11, weight: .regular)

    /// "Topic · 3 note blocks" under a popover title.
    static let popoverSubtitle = RetainTextStyle(size: 12, weight: .regular)

    /// The paragraph in the stop-confirmation popover.
    static let popoverBody = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.55)

    /// The accent-filled "Open summary" card.
    static let popoverCardTitle = RetainTextStyle(size: 15, weight: .semibold)

    static let popoverCardSubtitle = RetainTextStyle(size: 11.5, weight: .regular)

    /// The row along the bottom of the popover.
    static let popoverFooterAction = RetainTextStyle(size: 12.5, weight: .medium)

    /// A `⏎` hint at the right of a composer.
    static let enterHint = RetainTextStyle(size: 10.5, weight: .medium)

    /// A top-level row in the chapter rail.
    static let chapterEntry = RetainTextStyle(size: 13, weight: .semibold, lineHeight: 1.4)

    /// An indented row under it.
    static let chapterSubEntry = RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.45)

    /// The line under the chapter rail — "3 markers", "exam relevant".
    static let chaptersFooter = RetainTextStyle(size: 11.5, weight: .regular)

    /// The sentence above the first chat message.
    static let chatIntro = RetainTextStyle(size: 11.5, weight: .regular, lineHeight: 1.5)

    /// A source chip under a model answer.
    static let chatSourceChip = RetainTextStyle(size: 10.5, weight: .medium, monospacedDigits: true)

    /// "3 of 11" in the find bar, and the arrows beside it.
    static let findCount = RetainTextStyle(size: 12, weight: .regular, monospacedDigits: true)

    static let findAction = RetainTextStyle(size: 13, weight: .medium)

    /// The paragraph under a settings section heading.
    static let settingsDescription = RetainTextStyle(size: 13, weight: .regular, lineHeight: 1.5)

    /// The speech-model download card.
    static let settingsCardTitle = RetainTextStyle(size: 13.5, weight: .medium)

    static let settingsCardValue = RetainTextStyle(size: 12, weight: .regular)

    static let settingsCardCaption = RetainTextStyle(size: 11.5, weight: .regular)

    /// "−18 dB" beside the level meter.
    static let levelReadout = RetainTextStyle(size: 11.5, weight: .regular, monospacedDigits: true)

    /// The sentence under a dialog title.
    static let dialogBody = RetainTextStyle(size: 13, weight: .regular, lineHeight: 1.6)

    /// The caption beside a toggle.
    static let toggleCaption = RetainTextStyle(size: 12, weight: .regular)

    /// The term's name at the top of the library sidebar.
    static let librarySidebarTermTitle = RetainTextStyle(size: 13.5, weight: .semibold)

    /// "Oct 2025 – Mar 2026 · 4 courses" under it.
    static let librarySidebarTermSubtitle = RetainTextStyle(size: 11, weight: .regular)

    /// "Rename" beside the term.
    static let librarySidebarAction = RetainTextStyle(size: 11, weight: .medium)

    /// The recording count at the right of a course row.
    static let librarySidebarCount = RetainTextStyle(size: 11.5, weight: .regular)

    /// "+ New course" at the bottom of the sidebar.
    static let librarySidebarNewCourse = RetainTextStyle(size: 12.5, weight: .medium)

    /// The line beside the course heading in the library.
    static let libraryCourseSubtitle = RetainTextStyle(size: 12.5, weight: .regular)

    /// "by date ▾" beside the search field.
    static let librarySortControl = RetainTextStyle(size: 12, weight: .medium)

    /// The number column of the library table.
    static let tableLessonNumber = RetainTextStyle(size: 13, weight: .medium)

    /// The status column — "recording", "done".
    static let tableStatus = RetainTextStyle(size: 11.5, weight: .medium)

    // MARK: - Every style, for tests

    /// Every style above, paired with the name it is exposed under, so a test
    /// can walk the whole table.
    static let allStyles: [(name: String, style: RetainTextStyle)] = [
        ("noteHeading", noteHeading),
        ("libraryCourseHeading", libraryCourseHeading),
        ("settingsSectionHeading", settingsSectionHeading),
        ("dialogTitle", dialogTitle),
        ("popoverTitleReady", popoverTitleReady),
        ("popoverTitleSummarizing", popoverTitleSummarizing),
        ("popoverTitleRunning", popoverTitleRunning),
        ("timerLarge", timerLarge),
        ("metaValue", metaValue),
        ("uppercaseLabel", uppercaseLabel),
        ("noteParagraphRecording", noteParagraphRecording),
        ("noteParagraphDetail", noteParagraphDetail),
        ("noteBulletRecording", noteBulletRecording),
        ("noteBulletDetail", noteBulletDetail),
        ("noteBlockNumber", noteBlockNumber),
        ("transcriptLineMain", transcriptLineMain),
        ("transcriptLineRail", transcriptLineRail),
        ("transcriptLinePopover", transcriptLinePopover),
        ("timestampRail", timestampRail),
        ("timestampMain", timestampMain),
        ("annotationBody", annotationBody),
        ("chatMessageYours", chatMessageYours),
        ("chatMessageModel", chatMessageModel),
        ("tab", tab),
        ("segment", segment),
        ("sidebarRow", sidebarRow),
        ("tableCellTitle", tableCellTitle),
        ("tableCellOther", tableCellOther),
        ("fieldText", fieldText),
        ("fieldLabelSettings", fieldLabelSettings),
        ("fieldLabelDialog", fieldLabelDialog),
        ("buttonDialogPrimary", buttonDialogPrimary),
        ("buttonDialogSecondary", buttonDialogSecondary),
        ("buttonPopoverLarge", buttonPopoverLarge),
        ("buttonPanelFooter", buttonPanelFooter),
        ("captionSmall", captionSmall),
        ("captionMedium", captionMedium),
        ("captionLarge", captionLarge),
        ("titleBarSubtitle", titleBarSubtitle),
        ("titleBarTimer", titleBarTimer),
        ("titleBarStatus", titleBarStatus),
        ("titleBarButton", titleBarButton),
        ("titleBarTermPill", titleBarTermPill),
        ("chevron", chevron),
        ("writingLabel", writingLabel),
        ("railHeaderNote", railHeaderNote),
        ("popoverSubtitle", popoverSubtitle),
        ("popoverBody", popoverBody),
        ("popoverCardTitle", popoverCardTitle),
        ("popoverCardSubtitle", popoverCardSubtitle),
        ("popoverFooterAction", popoverFooterAction),
        ("enterHint", enterHint),
        ("chapterEntry", chapterEntry),
        ("chapterSubEntry", chapterSubEntry),
        ("chaptersFooter", chaptersFooter),
        ("chatIntro", chatIntro),
        ("chatSourceChip", chatSourceChip),
        ("findCount", findCount),
        ("findAction", findAction),
        ("settingsDescription", settingsDescription),
        ("settingsCardTitle", settingsCardTitle),
        ("settingsCardValue", settingsCardValue),
        ("settingsCardCaption", settingsCardCaption),
        ("levelReadout", levelReadout),
        ("dialogBody", dialogBody),
        ("toggleCaption", toggleCaption),
        ("librarySidebarTermTitle", librarySidebarTermTitle),
        ("librarySidebarTermSubtitle", librarySidebarTermSubtitle),
        ("librarySidebarAction", librarySidebarAction),
        ("librarySidebarCount", librarySidebarCount),
        ("librarySidebarNewCourse", librarySidebarNewCourse),
        ("libraryCourseSubtitle", libraryCourseSubtitle),
        ("librarySortControl", librarySortControl),
        ("tableLessonNumber", tableLessonNumber),
        ("tableStatus", tableStatus),
    ]
}

// MARK: - Applying a style

extension View {

    /// Font, tracking, line spacing and casing in one place, so no call site
    /// has to remember that a style is four modifiers rather than one.
    func retainStyle(_ style: RetainTextStyle) -> some View {
        font(style.font)
            .tracking(style.trackingPoints)
            .lineSpacing(style.lineSpacing)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

// MARK: - Fallback

nonisolated extension RetainFontWeight {

    /// Only used when the bundled face is missing, which is a build failure the
    /// assertion above catches first.
    var systemFallback: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}
