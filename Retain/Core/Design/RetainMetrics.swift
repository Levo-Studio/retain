import SwiftUI

// MARK: - Shadow

/// A CSS box-shadow, kept in CSS's own terms.
///
/// CSS gives a blur diameter; SwiftUI's `radius` is half of it. Keeping the
/// drawn value and doing the halving here means the number in this file can be
/// checked against the export without arithmetic.
nonisolated struct RetainShadow: Sendable, Equatable {

    let offsetY: CGFloat
    let blur: CGFloat
    let opacity: Double

    var color: Color { Color.black.opacity(opacity) }

    var radius: CGFloat { blur / 2 }

    /// How far the shadow reaches past the box it falls from.
    ///
    /// A borderless window has to be this much larger than the card it draws,
    /// or the shadow is clipped at the window's edge and the card looks stuck
    /// to the screen. Offset plus the full blur, which is as far as any of it
    /// can land.
    var extent: CGFloat { blur + offsetY }
}

// MARK: - Grids

/// A two-column form: a fixed label column and a flexible value column.
nonisolated struct RetainFormGrid: Sendable, Equatable {
    let labelColumn: CGFloat
    let rowGap: CGFloat
    let columnGap: CGFloat
    let maxWidth: CGFloat?

    init(labelColumn: CGFloat, rowGap: CGFloat, columnGap: CGFloat, maxWidth: CGFloat? = nil) {
        self.labelColumn = labelColumn
        self.rowGap = rowGap
        self.columnGap = columnGap
        self.maxWidth = maxWidth
    }
}

// MARK: - Metrics

/// Every size in `docs/design/`: radii, window and pane sizes, padding, grids
/// and the small drawn parts.
///
/// Named after what they are, never after what they measure — a `radius8` would
/// be renamed the day the design changes, and a `radiusSidebarRow` would not.
nonisolated enum RetainMetrics {

    // MARK: - Radii

    static let radiusWaveformBar: CGFloat = 2
    static let radiusCourseColourRail: CGFloat = 2

    static let radiusTermHighlight: CGFloat = 3
    static let radiusSearchHit: CGFloat = 3
    static let radiusProgressBar: CGFloat = 3

    static let radiusColourSwatch: CGFloat = 6
    static let radiusChatSourceChip: CGFloat = 6

    static let radiusHotkeyChip: CGFloat = 7

    static let radiusTextField: CGFloat = 8
    static let radiusRailSearchField: CGFloat = 8
    static let radiusSidebarRow: CGFloat = 8
    static let radiusSegment: CGFloat = 8
    static let radiusExportButton: CGFloat = 8

    /// The term picker in the library title bar.
    ///
    /// The README's radius table files this under 8. The board draws
    /// `border-radius:9px`, and where the two disagree the export wins.
    static let radiusStatusPill: CGFloat = 9

    static let radiusButton: CGFloat = 9
    static let radiusSearchField: CGFloat = 9
    static let radiusPopoverSecondaryButton: CGFloat = 9
    static let radiusReadyStateField: CGFloat = 9

    static let radiusDialogButton: CGFloat = 10
    static let radiusPopoverPrimaryButton: CGFloat = 10
    static let radiusChatComposer: CGFloat = 10
    static let radiusPopoverAnnotationBar: CGFloat = 10

    static let radiusWindow: CGFloat = 11
    static let radiusDownloadCard: CGFloat = 11
    static let radiusOpenSummaryCard: CGFloat = 11

    /// `12px 12px 4px 12px` — the bubble's bottom-trailing corner is the tail.
    static let radiusChatBubble: CGFloat = 12
    static let radiusChatBubbleTail: CGFloat = 4

    static let radiusToggle: CGFloat = 12

    static let radiusPopover: CGFloat = 13
    static let radiusDialog: CGFloat = 13

    static let radiusAnnotationBarRecording: CGFloat = 14

    /// The timer pill in the title bar. `999px` in CSS is "however round it
    /// gets"; in SwiftUI that is a capsule.
    static let radiusTimerPill: CGFloat = 999

    // MARK: - Windows and panes

    static let recordingWindowSize = CGSize(width: 1120, height: 720)

    /// Detail, transcript, library and settings all share one window size.
    static let detailWindowSize = CGSize(width: 1120, height: 700)

    /// The smallest a window may be dragged to.
    ///
    /// Not in the export, which draws one size per board. Without a floor a
    /// window can be pulled down to nothing and every fixed measure in it —
    /// the 330-point rail, the meta strip's three columns — starts overlapping
    /// the text. This is the width at which a collapsed rail still leaves a
    /// readable column, and the height at which the title bar, the strip, the
    /// tabs and two lines of notes are all still on screen.
    static let windowMinimumSize = CGSize(width: 680, height: 420)

    static let popoverWidth: CGFloat = 470
    static let dialogWidth: CGFloat = 430

    static let titleBarHeight: CGFloat = 38

    /// Room above the title bar's contents, for the buttons macOS draws.
    ///
    /// **This is what lets the bar hold the window's name on the left.** The
    /// system paints close, minimise and zoom over the top-left of the content
    /// view, centred about fourteen points down, and anything on the same line
    /// as them has to start to their right — which is why the name spent two
    /// rounds either indented past every column below it or on a row of its
    /// own. Given this much room above, the bar's one row sits underneath the
    /// buttons instead of beside them, and the name can begin on the same edge
    /// as the sidebar or the meta strip under it.
    static let titleBarTopRoom: CGFloat = 24

    /// Room under the title bar's contents, in **every** window.
    ///
    /// **Not drawn.** The export draws the bar 38 points flat, and at that
    /// height the pill and the buttons in it sit against the rule below with
    /// nothing between them. The owner asked for the gap on one window; it is
    /// applied to all of them, because a bar that is 38 in three windows and 52
    /// in the fourth is the kind of difference that is invisible until two of
    /// them are open side by side.
    ///
    /// It is inside `RetainTitleBar` rather than a parameter on it, so a window
    /// cannot forget it.
    static let titleBarBottomRoom: CGFloat = 14
    static let titleBarPadding = horizontal(14)
    static let titleBarGap: CGFloat = 9

    // `titleBarTitleGap` is in `RetainMetrics+Boards0607.swift`, which board 06
    // needs for the same bar.

    /// Between the controls at the trailing end of the title bar.
    static let titleBarTrailingGap: CGFloat = 8

    /// The logo left of the window title. Sized to the subtitle's cap height
    /// rather than to the bar, so it reads as part of the line of text it sits
    /// on instead of as a second thing in the bar.
    static let titleBarMark: CGFloat = 16

    /// Between the mark and the name beside it.
    static let titleBarMarkGap: CGFloat = 8

    /// The `Export` button.
    static let titleBarButtonPadding = edges(5, 10)
    /// The term picker in the library title bar, and the gap inside it.
    static let titleBarPillPadding = edges(5, 11)
    static let titleBarPillGap: CGFloat = 8

    static let transcriptRailWidth: CGFloat = 320
    static let chaptersRailWidth: CGFloat = 330
    static let librarySidebarWidth: CGFloat = 238
    static let settingsSidebarWidth: CGFloat = 210

    /// `1.6fr 1fr 1fr` — the three meta-strip cells, as flex weights.
    static let metaStripColumnWeights: [CGFloat] = [1.6, 1, 1]

    // MARK: - Padding

    static let metaStripCellFirst = edges(13, 34)
    static let metaStripCellOther = edges(13, 20)

    // The bottom is **not** zero, whatever the board shows. The export draws a
    // column that happens to end above the window's edge; a real recording
    // scrolls, and with no bottom inset the last bullet of the last section sat
    // flush against the frame with its descenders touching it.
    static let notesPaneRecording = edges(22, 34, notesPaneBottom)
    static let notesPaneDetail = edges(24, 34, notesPaneBottom)

    /// Room under the last line of the notes. The section gap, so the end of
    /// the column is spaced like the space between two sections rather than
    /// looking cut off.
    static let notesPaneBottom: CGFloat = 32
    static let transcriptPaneDetail = edges(18, 34, 0)

    static let libraryHeader = edges(18, 30, 14)
    static let libraryBody = edges(6, 30, 0)
    static let libraryCourseHeading = edges(20, 30, 10)
    static let libraryCourseHeadingGap: CGFloat = 12
    /// Between the search field and the sort control beside it.
    static let libraryHeaderGap: CGFloat = 14

    /// The term's name and period, above the courses in the sidebar.
    static let librarySidebarTermHeader = edges(0, 8, 12)
    static let librarySidebarTermSubtitleGap: CGFloat = 2
    /// Between a course's colour rail, its name and its count.
    static let librarySidebarRowGap: CGFloat = 10
    static let librarySidebarNewCoursePadding = edges(9, 9)

    static let settingsPane = edges(26, 34, 0)
    static let settingsSectionGap: CGFloat = 24
    /// A section that follows a rule keeps this much air above it.
    static let settingsSectionRuleGap: CGFloat = 22

    static let sidebarPadding = edges(16, 12)

    static let railHeaderRecording = edges(16, 20, 10)
    static let railHeaderDetail = edges(14, 18, 10)
    static let railBodyRecording = horizontal(20)
    static let railBodyDetail = horizontal(18)

    static let popoverHeaderRunning = edges(18, 18, 16)
    static let popoverHeaderPaused = edges(20, 20, 18)
    static let popoverHeaderSummarizing = edges(22, 18, 20)
    static let popoverHeaderReady = edges(16, 16, 14)
    static let popoverHeaderStopConfirmation = edges(22, 22, 20)

    static let dialogHeader = edges(20, 20, 16)
    /// Slightly tighter where a rule follows the header.
    static let dialogHeaderWithRule = edges(20, 20, 14)
    static let dialogBody = edges(16, 20)
    static let dialogFooter = edges(0, 20, 18)
    static let dialogFooterGap: CGFloat = 10

    static let tabBarPadding = horizontal(34)

    // The live transcript, now that it has the window to itself rather than a
    // 330-point rail. The export has no board for it — it draws the rail — so
    // these are the detail window's own reading measures, which is where the
    // transcript is read at length everywhere else in the app.

    /// How wide a line of transcript is allowed to get. A window on a 27-inch
    /// screen would otherwise run a sentence the whole way across, and a line
    /// that long is one the eye loses its place in.
    static let transcriptFullColumn: CGFloat = 720

    static let transcriptFullPadding = edges(28, 34, 28)

    /// Around the annotation bar, now that it sits against the window rather
    /// than inside a notes column. The transcript's own side inset, so the bar
    /// and the words above it share an edge.
    static let annotationBarInset = edges(0, 34, 22)

    /// Between two lines of the live transcript.
    static let transcriptFullLineGap: CGFloat = 14

    // The screen between a lecture ending and its notes existing. Not drawn on
    // any board — the export has no state for it, because in the export the
    // notes are already there.

    static let processingColumn: CGFloat = 420
    static let processingGap: CGFloat = 10
    static let processingStepGap: CGFloat = 14
    static let processingRowGap: CGFloat = 12
    /// Wide enough for the moving dots, so the three rows do not shift
    /// sideways as each step starts and finishes.
    static let processingMarkerColumn: CGFloat = 26

    /// The progress bar under a step that reports a real fraction, at the
    /// speech-model download's own height.
    static let processingBarHeight: CGFloat = 4
    static let processingBarGap: CGFloat = 8

    /// Between the "no notes yet" sentence and what can be done about it.
    static let detailEmptyNotesGap: CGFloat = 14

    /// The recording window's name, on the same left edge as its tabs and its
    /// meta strip. It has no sidebar to sit at the top of, so it is its own row
    /// under the title bar instead.
    /// The seam between two merged recordings in the transcript.
    ///
    /// **Not drawn.** The room above is what separates it from the last line of
    /// the part before — enough that it reads as a break and not as a caption
    /// on that line — and the gap is the one between a label and its value
    /// everywhere else.
    static var transcriptPartHeadingGap: CGFloat { metaValueGap }
    static let transcriptPartHeadingRoom: CGFloat = 26

    /// The corner of the tick's box. The smallest radius in the export, which
    /// is what a 16-point box wants — anything rounder reads as a pill.
    static let radiusCheckbox: CGFloat = 4

    /// The tick in front of a recording's title while several are being picked.
    ///
    /// **Not drawn.** The export's table has no selection state. The box is the
    /// status dot's size taken up to something a pointer can hit, and the gap
    /// is the table's own column gap, so the title moves right by one column
    /// gap and lands on a rhythm the table already has.
    static let selectionTickSize: CGFloat = 16
    static var selectionTickGap: CGFloat { libraryTableGap }

    static let tabGap: CGFloat = 22
    static let tabPadding = edges(11, 0)

    /// The button at the trailing end of the tab bar that folds the rail away.
    ///
    /// **Not drawn in the export.** Sized to sit on the tabs' own baseline
    /// without making the bar taller: the tab padding's height, and enough
    /// width either side of a single glyph to be a target rather than a
    /// character somebody has to aim at.
    static let railTogglePadding = edges(11, 9)

    static let sidebarRowLibrary = edges(8, 9)
    static let sidebarRowSettings = edges(8, 10)
    static let sidebarRowGap: CGFloat = 3

    static let tableHeaderRow = edges(8, 10)
    static let tableRow = edges(13, 10)

    static let fieldPadding = edges(8, 11)
    static let searchFieldPadding = edges(8, 12)
    static let railSearchFieldPadding = edges(7, 11)

    static let dialogButtonPadding = edges(9, 16)
    static let popoverLargeButtonPadding = edges(12, 0)
    static let panelFooterButtonPadding = edges(8, 0)
    static let panelFooterButtonGap: CGFloat = 9

    static let segmentPadding = edges(7, 0)
    static let segmentGap: CGFloat = 3

    /// The Chapters/Chat segment sits under the rail's search field on board
    /// 03 and at the top of the rail on board 04, which draws no field.
    static let railSegmentUnderSearch = edges(0, 18, 12)
    static let railSegmentAtTop = edges(14, 18, 12)

    static let annotationBarRecordingPadding = edges(11, 15)
    static let annotationBarRecordingMargin = edges(14, 34, 20)
    static let annotationBarGap: CGFloat = 12
    static let annotationBarPopoverPadding = edges(9, 12)
    static let annotationBarPopoverGap: CGFloat = 10

    static let chatComposerPadding = edges(9, 12)
    static let chatComposerGap: CGFloat = 10
    static let chatBubblePadding = edges(9, 12)

    /// Around the composer, inside the rail.
    static let chatComposerMargin = edges(12, 18, 14)
    /// The rail's scrolling body, between the segment and the composer.
    static let chatRailBody = edges(4, 18, 0)

    /// `max-width:86%` on a question, `92%` on an answer. A question is a
    /// bubble and reads as a shape; an answer is prose and takes the measure.
    static let chatBubbleMaxWidthFraction: CGFloat = 0.86
    static let chatAnswerMaxWidthFraction: CGFloat = 0.92

    static let chatSourceChipPadding = edges(2, 6)
    static let chatSourceChipGap: CGFloat = 6
    /// Between the answer and the chips under it.
    static let chatSourceChipTopGap: CGFloat = 7

    /// Between the three dots of the typing indicator.
    static let typingDotGap: CGFloat = 5

    // MARK: - Gaps between repeated rows

    /// Between transcript lines in the recording rail.
    static let transcriptRailLineGap: CGFloat = 12
    /// Between transcript lines in the popover.
    static let transcriptPopoverLineGap: CGFloat = 10
    /// Between transcript lines in the main pane of the transcript tab.
    static let transcriptMainLineGap: CGFloat = 15
    /// Between rows of the chapter rail.
    static let chapterRowGap: CGFloat = 4
    /// A chapter row's own padding: the first row in the rail, and every one
    /// after it, which the export gives more air above.
    static let chapterRowFirst = edges(6, 0)
    static let chapterRowLater = edges(10, 0, 6)
    static let chapterRowLaterTopGap: CGFloat = 6
    /// Between a chapter's time and its title.
    static let chapterRowGapToTitle: CGFloat = 10
    static let chaptersFooterPadding = edges(12, 18)
    /// Between chat messages.
    static let chatMessageGap: CGFloat = 12

    /// The label above a transcript line and the line itself.
    static let transcriptLabelGapRail: CGFloat = 2
    static let transcriptLabelGapMain: CGFloat = 3

    /// A meta-strip label and the value under it.
    static let metaValueGap: CGFloat = 3

    // MARK: - Find bar

    static let findBarPadding = edges(14, 34)
    static let findBarGap: CGFloat = 12

    // MARK: - Grids

    static let settingsForm = RetainFormGrid(labelColumn: 160, rowGap: 12, columnGap: 18, maxWidth: 640)
    static let dialogForm = RetainFormGrid(labelColumn: 104, rowGap: 11, columnGap: 16)

    /// `54px 1fr 120px 96px 84px`, gap 14. The first column is the `Nr.` the
    /// export draws; the owner has since dropped lesson numbers, so a screen
    /// may well use only the last four.
    static let libraryTableNumberColumn: CGFloat = 54
    static let libraryTableDateColumn: CGFloat = 120
    static let libraryTableDurationColumn: CGFloat = 96
    static let libraryTableStatusColumn: CGFloat = 84
    static let libraryTableGap: CGFloat = 14

    /// `74px 1fr`, gap 16 — timestamp, then the line.
    static let transcriptTimestampColumn: CGFloat = 74
    static let transcriptLineGap: CGFloat = 16

    /// A line the user marked hangs its rule out into the pane's padding —
    /// `margin-left:-16px` — and pads the text back in by `leftRuleGapMain`.
    static let transcriptMarkerRuleInset: CGFloat = 16

    // MARK: - Small parts

    static let trafficLightDiameter: CGFloat = 10

    static let statusDotPopover: CGFloat = 8
    static let statusDotDialog: CGFloat = 8
    static let statusDotSettings: CGFloat = 7
    /// Marker dots, the dot on a chapter row, and the chat typing dots.
    static let statusDotSmall: CGFloat = 5

    static let waveformBarWidth: CGFloat = 3
    static let waveformBarGap: CGFloat = 2
    static let waveformHeightTitleBar: CGFloat = 13
    static let waveformHeightReady: CGFloat = 16
    static let waveformHeightPopover: CGFloat = 20

    static let pauseGlyphSmall = CGSize(width: 3, height: 12)
    static let pauseGlyphLarge = CGSize(width: 3, height: 13)
    static let pauseGlyphRadius: CGFloat = 1
    static let pauseGlyphGap: CGFloat = 3

    static let progressBarHeightSummarizing: CGFloat = 4
    /// The speech-model download and the microphone level meter.
    static let progressBarHeightDownload: CGFloat = 5

    /// The rule down the left of an annotation, an audience line, or a top
    /// level chapter row.
    static let leftRuleWidth: CGFloat = 2
    static let leftRuleGapRail: CGFloat = 11
    static let leftRuleGapMain: CGFloat = 14

    static let annotationRuleRecording = CGSize(width: 2, height: 16)
    static let annotationRulePopover = CGSize(width: 2, height: 15)

    static let caretWidth: CGFloat = 2
    static let caretHeightNotes: CGFloat = 15
    static let caretHeightRail: CGFloat = 12

    /// The air between the last word and the caret — `margin-left` in the
    /// export.
    static let caretLeadingGapNotes: CGFloat = 4
    static let caretLeadingGapRail: CGFloat = 3

    /// How far the caret hangs below the baseline. The export writes it as
    /// `vertical-align`, which is a shift of the box rather than a height.
    static let caretBaselineDropNotes: CGFloat = 3
    static let caretBaselineDropRail: CGFloat = 2

    static let courseColourRail = CGSize(width: 3, height: 14)

    static let toggleSize = CGSize(width: 34, height: 20)
    static let toggleKnobDiameter: CGFloat = 16
    static let toggleInset: CGFloat = 2

    static let colourSwatchSize = CGSize(width: 20, height: 20)
    static let colourSwatchSelectionWidth: CGFloat = 2
    static let colourSwatchSelectionOffset: CGFloat = 2

    static let activeTabUnderlineHeight: CGFloat = 2

    /// How far a sub-entry in the chapter rail sits in from a heading row.
    static let chapterIndent: CGFloat = 26

    /// The emphasised term's background, `0 3px` in the export.
    static let termHighlightPadding = edges(0, 3)

    // MARK: - Note blocks

    /// Between the block number and the heading beside it.
    static let noteHeadingNumberGap: CGFloat = 11

    /// Body and bullets sit past the number on the recording screen, and flush
    /// on the detail screen, which draws no numbers.
    static let noteBodyIndentRecording: CGFloat = 30
    static let noteBodyIndentDetail: CGFloat = 0

    static let noteParagraphGapRecording: CGFloat = 8
    static let noteParagraphGapDetail: CGFloat = 9
    static let noteBulletGapRecording: CGFloat = 8
    static let noteBulletGapDetail: CGFloat = 11

    /// The bullet's own hanging indent, inside the body indent.
    static let noteBulletIndentRecording: CGFloat = 18
    static let noteBulletIndentDetail: CGFloat = 19

    /// Between one note block and the next.
    static let noteBlockGapRecording: CGFloat = 22
    /// Before a second heading in the finished notes.
    static let noteBlockGapDetail: CGFloat = 24

    /// The annotation card inside the notes.
    static let noteAnnotationGap: CGFloat = 13

    /// How far below the top of the notes column a block counts as the one
    /// being read, for the chapter rail's accent rule.
    ///
    /// Not a dimension the export draws — it is not drawn at all — but it is a
    /// number, and numbers live here. It is the column's own top padding plus
    /// about a heading's height: a block whose heading has just appeared is not
    /// the block anybody is reading yet.
    static let notesReadingLine: CGFloat = 140
    static let noteAnnotationLabelGap: CGFloat = 3

    /// Paragraph width caps, in `ch`. Resolved against the paragraph's own
    /// font, because `ch` is a measure in the text's own zero.
    static let noteParagraphWidthRecording: CGFloat = 64
    static let noteParagraphWidthDetail: CGFloat = 70

    /// The widest the detail measure grows to when the window is made wide.
    ///
    /// The export draws one window width and therefore one measure. On a
    /// display twice that wide, 70ch leaves most of the column empty, and the
    /// owner asked for the space to be used. It is a ceiling and not a target:
    /// a line of prose stops being readable somewhere past a hundred
    /// characters, so the column grows with the window and then stops.
    static let noteParagraphWidthDetailWide: CGFloat = 96
    static let settingsDescriptionWidth: CGFloat = 70

    // MARK: - Opacity ladder

    // MARK: - Board 01, the recording window

    // Read out of `Retain - Alle Screens.dc.html` rather than the README's
    // tables, which name the paddings of the panes and leave the gaps inside a
    // row to the board.

    /// Between the groups at the right of the recording window's title bar —
    /// the meter, the power reading and the timer pill.
    static let titleBarGroupGap: CGFloat = 14

    /// Between the meter and the words beside it.
    static let titleBarSpeechGap: CGFloat = 7

    /// The pill is tighter on the side the dot sits on: `3px 11px 3px 8px`.
    static let titleBarTimerPillPadding = edges(3, 8, 3, 11)
    static let titleBarTimerPillGap: CGFloat = 8

    /// The recording dot inside that pill. Smaller than the popover's 8px dot.
    static let statusDotTimerPill: CGFloat = 7

    /// Between a meta-strip value and the `▾` that opens its menu.
    static let metaChevronGap: CGFloat = 7

    /// The course picker in the detail meta strip.
    ///
    /// **Zero, on purpose.** The export draws the course there as plain text,
    /// and the owner asked for it to open a list without becoming a field. Any
    /// padding at all would push the value off the baseline the two cells
    /// beside it sit on, and the row would read as a form rather than as three
    /// facts. The `▾` is the whole of what says there is a list behind it.
    static let metaPickerPadding = EdgeInsets()

    /// "writing …" sits in the heading's own row, at the heading gap.
    static let noteWritingLabelGap: CGFloat = 11

    /// The `⌘⇧M · 2 markers` chip inside the annotation bar.
    static let annotationChipPadding = edges(4, 9)

    /// The row of buttons along the bottom of the transcript rail.
    static let railFooterPadding = edges(12, 20)

    // MARK: - Board 02, the popover

    /// The status row at the top of a popover header — dot, label, and the
    /// power reading pushed to the right.
    static let popoverStatusRowGap: CGFloat = 9

    /// Between that row and the title under it. The paused state sits one point
    /// lower than the running one, which is drawn and not rounded away.
    static let popoverTitleGapRunning: CGFloat = 10
    static let popoverTitleGapPaused: CGFloat = 11
    static let popoverTitleGapSummarizing: CGFloat = 11
    static let popoverTitleGapStopConfirmation: CGFloat = 9

    /// Between a popover title and the line under it.
    static let popoverSubtitleGap: CGFloat = 3
    static let popoverSubtitleGapSummarizing: CGFloat = 4
    static let popoverBodyGapStopConfirmation: CGFloat = 6

    /// Between the title block and the meter row under it, and between the
    /// meter and the buttons beside it.
    static let popoverMeterGap: CGFloat = 14
    static let popoverMeterRowGap: CGFloat = 12

    /// How many bars each meter is drawn with. The export draws a fixed count
    /// rather than a bar per unit of time, so the count is the geometry.
    static let meterBarCountTitleBar = 5
    static let meterBarCountReady = 5
    static let meterBarCountPopover = 17

    static let popoverPauseButtonPadding = edges(8, 15)
    static let popoverPauseButtonGap: CGFloat = 8
    static let popoverStopButtonPadding = edges(8, 14)
    static let popoverResumeButtonPadding = edges(8, 16)
    static let popoverRecordButtonPadding = edges(9, 15)

    /// The two large buttons of the stop confirmation.
    static let popoverLargeButtonGap: CGFloat = 9
    static let popoverButtonRowGap: CGFloat = 10
    static let popoverButtonRowGapStopConfirmation: CGFloat = 16

    /// The live-transcript section of the running state.
    static let popoverTranscriptHeader = edges(14, 18, 8)
    static let popoverTranscriptBody = edges(0, 18, 14)

    /// The last line before the pause, which is set one point wider because the
    /// paused header is.
    static let popoverLastLineHeader = edges(14, 20, 8)
    static let popoverLastLineBody = edges(0, 20, 16)

    static let popoverFooterPadding = edges(12, 18)
    static let popoverFooterPaddingPaused = edges(12, 20)

    /// The body of the summarizing state, under the progress bar.
    static let popoverSummarizingBody = edges(16, 18, 18)

    /// The accent-filled "Open summary" card.
    static let popoverCardPadding = edges(14, 16)
    static let popoverCardGap: CGFloat = 12
    static let popoverCardSubtitleGap: CGFloat = 2

    /// "keep running in the background", under that card.
    static let popoverBackgroundActionGap: CGFloat = 10

    /// The ready state: the course field and the Record button beside it, and
    /// the level row under them.
    static let popoverReadyRowGap: CGFloat = 10
    static let popoverReadyRowTopGap: CGFloat = 9
    static let popoverReadyFooter = edges(14, 16)
    static let popoverReadyFooterGap: CGFloat = 11

    // MARK: - Shadows

    static let windowShadow = RetainShadow(offsetY: 18, blur: 44, opacity: 0.5)
    static let popoverShadow = RetainShadow(offsetY: 18, blur: 44, opacity: 0.55)
    static let dialogShadow = RetainShadow(offsetY: 22, blur: 50, opacity: 0.6)

    // MARK: - CSS shorthands

    /// `padding: <vertical> <horizontal>`.
    private static func edges(_ vertical: CGFloat, _ horizontal: CGFloat) -> EdgeInsets {
        EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    /// `padding: <top> <horizontal> <bottom>`.
    private static func edges(_ top: CGFloat, _ horizontal: CGFloat, _ bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal)
    }

    /// A padding whose two sides differ. CSS writes the four-value shorthand
    /// clockwise from the top and SwiftUI names its edges, so the order here is
    /// SwiftUI's and the one call site that needs it says which is which.
    private static func edges(
        _ top: CGFloat,
        _ leading: CGFloat,
        _ bottom: CGFloat,
        _ trailing: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// `padding: 0 <horizontal>`.
    private static func horizontal(_ horizontal: CGFloat) -> EdgeInsets {
        EdgeInsets(top: 0, leading: horizontal, bottom: 0, trailing: horizontal)
    }
}
