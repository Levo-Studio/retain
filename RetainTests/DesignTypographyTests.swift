import AppKit
import CoreText
import Foundation
import Testing

@testable import Retain

@Suite("Typography")
struct RetainTypographyTests {

    /// The failure this exists for: the font does not register, Core Text hands
    /// back a system face for the unknown name, every screen still draws text,
    /// and nothing looks broken in a screenshot while every measured width in
    /// the design is wrong.
    ///
    /// It fails when `Retain/Resources/Fonts/DMSans-Variable.ttf` is missing
    /// from the bundle or `ATSApplicationFontsPath` no longer points at the
    /// directory it ends up in.
    @Test("DM Sans is in the bundle and registered")
    func theBundledFaceLoaded() {
        #expect(RetainTypography.isDesignFontAvailable)
    }

    @Test("A style is set in DM Sans and not in a fallback")
    func stylesUseTheBundledFace() {
        for (name, style) in RetainTypography.allStyles {
            #expect(style.nsFont.familyName == RetainTypography.familyName, "\(name)")
        }
    }

    /// DM Sans is one variable file, so 500 and 600 are interpolations on the
    /// `wght` axis rather than separate faces. If the axis were being ignored,
    /// every weight would come out the same width.
    @Test("The four weights really are four weights")
    func weightsAreDistinct() {
        let text = "Working Set" as NSString
        var widths: [Double] = []

        for weight in RetainFontWeight.allCases {
            let font = RetainTypography.nsFont(size: 15, weight: weight)
            widths.append(Double(text.size(withAttributes: [.font: font]).width))
        }

        for (lighter, heavier) in zip(widths, widths.dropFirst()) {
            #expect(heavier > lighter)
        }
    }

    /// The board is drawn in a browser with optical sizing on, which ties
    /// `opsz` to the font size. Two sizes of the same weight therefore are not
    /// the same outline scaled — if they were, the axis would not be reaching
    /// the font.
    @Test("Optical size follows the point size")
    func opticalSizeFollowsPointSize() {
        let small = RetainTypography.nsFont(size: 10.5, weight: .regular)
        let large = RetainTypography.nsFont(size: 26, weight: .regular)

        let text = "00:47:12" as NSString
        let smallWidthPerPoint = Double(text.size(withAttributes: [.font: small]).width) / 10.5
        let largeWidthPerPoint = Double(text.size(withAttributes: [.font: large]).width) / 26

        #expect(abs(smallWidthPerPoint - largeWidthPerPoint) > 0.001)
    }

    /// A `line-height` in the export is a line box; SwiftUI's `lineSpacing` is
    /// the gap added on top of the font's own. The two only agree if the
    /// subtraction happens.
    @Test("Line spacing is the line box minus the font's own line height")
    func lineSpacingIsTheDifference() {
        let paragraph = RetainTypography.noteParagraphDetail
        let natural = RetainTypography.naturalLineHeight(of: paragraph)

        #expect(paragraph.lineSpacing > 0)
        #expect(abs(paragraph.lineSpacing - (15 * 1.7 - natural)) < 0.001)
    }

    @Test("A style without a line height adds no spacing")
    func noLineHeightNoSpacing() {
        #expect(RetainTypography.metaValue.lineSpacing == 0)
        #expect(RetainTypography.dialogTitle.lineSpacing == 0)
    }

    /// Tracking is a fraction of the size in CSS and a point value in SwiftUI.
    @Test("Tracking converts from em to points")
    func trackingConvertsToPoints() {
        #expect(abs(RetainTypography.noteHeading.trackingPoints - (-0.015 * 22)) < 0.0001)
        #expect(abs(RetainTypography.uppercaseLabel.trackingPoints - (0.07 * 10.5)) < 0.0001)
        #expect(RetainTypography.metaValue.trackingPoints == 0)
    }

    /// The export's type table, transcribed. A row read off by the wrong line
    /// is the kind of mistake nothing else here would notice.
    @Test("The type table is what the README says it is")
    func theTypeTable() {
        #expect(RetainTypography.noteHeading == RetainTextStyle(size: 22, weight: .bold, lineHeight: 1.25, tracking: -0.015))
        #expect(RetainTypography.libraryCourseHeading == RetainTextStyle(size: 21, weight: .bold, tracking: -0.015))
        #expect(RetainTypography.settingsSectionHeading == RetainTextStyle(size: 17, weight: .bold, tracking: -0.01))
        #expect(RetainTypography.dialogTitle == RetainTextStyle(size: 17, weight: .semibold))
        #expect(RetainTypography.popoverTitleReady == RetainTextStyle(size: 19, weight: .semibold, tracking: -0.01))
        #expect(RetainTypography.popoverTitleSummarizing == RetainTextStyle(size: 18, weight: .semibold))
        #expect(RetainTypography.popoverTitleRunning == RetainTextStyle(size: 16, weight: .semibold))
        #expect(RetainTypography.metaValue == RetainTextStyle(size: 14.5, weight: .medium))
        #expect(RetainTypography.noteParagraphRecording == RetainTextStyle(size: 15, weight: .regular, lineHeight: 1.66))
        #expect(RetainTypography.noteBulletRecording == RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.6))
        #expect(RetainTypography.noteBulletDetail == RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.68))
        #expect(RetainTypography.transcriptLineMain == RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.65))
        #expect(RetainTypography.transcriptLineRail == RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.55))
        #expect(RetainTypography.transcriptLinePopover == RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.5))
        #expect(RetainTypography.annotationBody == RetainTextStyle(size: 14.5, weight: .regular, lineHeight: 1.55))
        #expect(RetainTypography.chatMessageYours == RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.55))
        #expect(RetainTypography.chatMessageModel == RetainTextStyle(size: 12.5, weight: .regular, lineHeight: 1.6))
        #expect(RetainTypography.noteBlockNumber == RetainTextStyle(size: 11, weight: .medium, monospacedDigits: true))
    }

    /// Every timer, timestamp, duration and counter in the export carries
    /// `tabular-nums`, and every one of them here has to say so.
    @Test("Timers, timestamps and counters have tabular figures")
    func tabularFiguresWhereTheExportHasThem() {
        let tabular = [
            "timerLarge", "noteBlockNumber", "timestampRail", "timestampMain",
            "titleBarTimer", "chatSourceChip", "findCount", "levelReadout",
        ]

        for name in tabular {
            let style = RetainTypography.allStyles.first { $0.name == name }?.style
            #expect(style?.monospacedDigits == true, "\(name)")
        }
    }

    @Test("Only the uppercase label is uppercased")
    func onlyTheLabelIsUppercased() {
        let uppercased = RetainTypography.allStyles.filter { $0.style.uppercase }.map(\.name)
        #expect(uppercased == ["uppercaseLabel"])
    }

    /// The paragraph caps are `64ch` and `70ch` — a measure in the text's own
    /// zero, which is why they cannot be written down as points.
    @Test("A ch is the width of the paragraph's own zero")
    func chIsMeasuredInTheParagraphsFont() {
        let width = RetainTypography.chWidth(of: RetainTypography.noteParagraphDetail)
        let font = RetainTypography.nsFont(size: 15, weight: .regular)
        let zero = ("0" as NSString).size(withAttributes: [.font: font]).width

        #expect(abs(width - Double(zero)) < 0.6)
        #expect(width > 0)
    }

    @Test("Every style is listed exactly once")
    func everyStyleIsListedOnce() {
        let names = RetainTypography.allStyles.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
