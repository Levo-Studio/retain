import SwiftUI

/// The sizes boards 06 and 07 draw that the README's tables do not name.
///
/// `docs/design/README.md` collects the values that repeat across boards. These
/// do not repeat — they are the settings pane's own vertical rhythm and the
/// dialog's own one — so they were never lifted into a table, and
/// `Retain - Alle Screens.dc.html` is the only place they exist. The README and
/// the HTML do not disagree here; the README is simply silent, and the HTML
/// wins by default.
///
/// They live in a separate file from `RetainMetrics` for a reason that has
/// nothing to do with design: the settings and dialog boards are built beside
/// two other boards in their own branches, and three branches appending to one
/// file is three conflicts. Fold this back into `RetainMetrics` when the
/// branches have landed.
nonisolated extension RetainMetrics {

    // MARK: - Title bar

    /// Between the last traffic light and the window title. Wider than the
    /// 9px gap the lights keep between themselves, so the label does not read
    /// as a fourth one.
    static let titleBarTitleGap: CGFloat = 13

    // MARK: - Settings pane

    /// A section heading and the sentence under it.
    static let settingsHeadingDescriptionGap: CGFloat = 4

    /// A description and the form under it.
    static let settingsFormGapAfterDescription: CGFloat = 16

    /// A heading and the form under it, where the section has no description.
    /// The microphone section is the one that does this.
    static let settingsFormGapAfterHeading: CGFloat = 14

    /// A description and the card under it — the speech-model download.
    static let settingsCardGapAfterDescription: CGFloat = 14

    /// The model picker and the "Test connection" button beside it.
    static let settingsModelRowGap: CGFloat = 10

    /// The status dot and the line of text beside it.
    static let settingsStatusRowGap: CGFloat = 8

    /// The level meter and the dB readout beside it.
    static let settingsLevelRowGap: CGFloat = 10

    /// A button that sits inside a form row rather than in a footer. Tighter
    /// vertically than a dialog button and narrower horizontally, so it lines
    /// up with the field beside it.
    static let settingsInlineButtonPadding = EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)

    // MARK: - Speech-model download card

    static let settingsDownloadCardPadding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

    /// The card's title row and the progress bar under it.
    static let settingsCardProgressGap: CGFloat = 10

    /// The progress bar and the caption under it.
    static let settingsCardCaptionGap: CGFloat = 8

    // MARK: - Dialogs

    /// The uppercase label and the title under it.
    static let dialogLabelTitleGap: CGFloat = 8

    /// The same gap where the label sits in a row with a status dot. One point
    /// more, because the row is taller than the label alone.
    static let dialogStatusLabelTitleGap: CGFloat = 9

    /// The title and the body paragraph under it.
    static let dialogTitleBodyGap: CGFloat = 8

    /// The status dot and the label beside it, in the dialog that has one.
    static let dialogStatusRowGap: CGFloat = 9

    /// A footer that follows a form body rather than a paragraph. The form's
    /// own bottom padding is already there, so this adds four points instead of
    /// the sixteen `dialogFooter` assumes.
    static let dialogFooterAfterForm = EdgeInsets(top: 4, leading: 20, bottom: 18, trailing: 20)

    /// The two month fields of a period, side by side.
    static let dialogPeriodFieldGap: CGFloat = 8

    /// Between two colour swatches.
    static let dialogColourSwatchGap: CGFloat = 8

    /// The toggle and the sentence beside it.
    static let dialogToggleRowGap: CGFloat = 10
}
