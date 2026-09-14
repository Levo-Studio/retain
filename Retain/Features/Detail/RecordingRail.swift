import SwiftUI

/// The 330-point rail down the right of boards 03 and 04.
///
/// One rail, two things in it. The segment at the top switches between the
/// chapters — which are the notes' own headings, read back — and a conversation
/// about the recording.
struct RecordingRail: View {

    @Bindable var model: RecordingDetailModel

    var body: some View {
        VStack(spacing: 0) {
            if model.rail == .chapters {
                searchField
                    .padding(RetainMetrics.railHeaderDetail)
            }

            segment
                .padding(
                    model.rail == .chapters
                        ? RetainMetrics.railSegmentUnderSearch
                        : RetainMetrics.railSegmentAtTop
                )

            switch model.rail {
            case .chapters: ChapterList(model: model)
            case .chat: ChatList(model: model)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RetainPalette.surfaceRail)
    }

    // MARK: - The field above the segment

    /// Board 03 draws this field and no result state for it, so it does the one
    /// thing the list under it can show: it filters the chapters, keeping the
    /// ones whose notes or whose stretch of the transcript match.
    private var searchField: some View {
        RetainTextField(
            placeholder: DetailCopy.railSearchPlaceholder,
            text: $model.railQuery,
            cornerRadius: RetainMetrics.radiusButton,
            padding: RetainMetrics.railSearchFieldPadding,
            textStyle: RetainTypography.captionLarge
        )
    }

    // MARK: - Chapters / Chat

    private var segment: some View {
        HStack(spacing: RetainMetrics.segmentGap) {
            option(.chapters, title: DetailCopy.chaptersSegment)
            option(.chat, title: DetailCopy.chatSegment)
        }
    }

    private func option(_ which: RecordingDetailModel.Rail, title: String) -> some View {
        let isActive = model.rail == which

        return Button {
            model.rail = which
        } label: {
            Text(verbatim: title)
                .retainStyle(RetainTypography.segment)
                .foregroundStyle(isActive ? RetainPalette.inkPrimary : RetainPalette.inkLabel)
                .frame(maxWidth: .infinity)
                .padding(RetainMetrics.segmentPadding)
        }
        .buttonStyle(
            RetainSurfaceButtonStyle(
                resting: isActive ? RetainPalette.selectedRowSwatch : nil,
                cornerRadius: RetainMetrics.radiusSegment
            )
        )
    }
}

// MARK: - The chapters

/// The rail board 03 draws, at **one level**.
///
/// The board shows two — headings with indented sub-entries under them — and
/// only one of them exists. A chapter is a note block's heading, and a block
/// has exactly one heading; there is nothing below it to indent, and inventing
/// a second level would mean asking the model for something it was deliberately
/// never asked for. `RetainMetrics.chapterIndent` is still in the design layer
/// for the day the notes gain a structure that earns it.
struct ChapterList: View {

    let model: RecordingDetailModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RetainMetrics.chapterRowGap) {
                    if model.filteredChapters.isEmpty {
                        Text(verbatim: DetailCopy.noChapters)
                            .retainStyle(RetainTypography.chaptersFooter)
                            .foregroundStyle(RetainPalette.inkLabel)
                            .padding(.top, RetainMetrics.chapterRowFirst.top)
                    } else {
                        ForEach(Array(model.filteredChapters.enumerated()), id: \.element.id) { index, chapter in
                            ChapterRow(
                                chapter: chapter,
                                isCurrent: chapter.id == model.currentChapter?.id,
                                isFirst: index == 0
                            ) {
                                model.show(chapter: chapter)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RetainMetrics.railBodyDetail)
            }
            .scrollContentBackground(.hidden)

            footer
        }
        .frame(maxHeight: .infinity)
    }

    /// What the rail says about the recording as a whole. The export draws two
    /// pieces of text and no control, so that is what this is: the count of
    /// what the user marked, and the word the design puts at the other end.
    private var footer: some View {
        HStack(spacing: 0) {
            Text(verbatim: DetailCopy.markers(model.markerCount))
            Spacer(minLength: 0)
            Text(verbatim: DetailCopy.examRelevant)
        }
        .retainStyle(RetainTypography.chaptersFooter)
        .foregroundStyle(RetainPalette.inkLabel)
        .padding(RetainMetrics.chaptersFooterPadding)
        .overlay(alignment: .top) { RetainDivider() }
    }
}

/// One chapter: the minute it starts at, its heading, and an amber dot when the
/// user marked something inside it.
///
/// Clicking it brings the notes forward at that card. It used to start the
/// audio at that minute, and there is no audio — but a rail of chapters is a
/// list of places to go, so it still goes there, and the minute it draws is
/// still when that part of the lecture began.
struct ChapterRow: View {

    let chapter: NoteChapter
    let isCurrent: Bool
    let isFirst: Bool
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(isCurrent ? RetainPalette.accent : RetainPalette.lineControlBorderEmphasised)
                    .frame(width: RetainMetrics.leftRuleWidth)

                HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.chapterRowGapToTitle) {
                    Text(verbatim: RetainTimeFormat.hourMinute(chapter.time))
                        .retainStyle(RetainTypography.timestampRail)
                        .foregroundStyle(chapter.hasMarker ? RetainPalette.amberInk : RetainPalette.inkLabel)

                    Text(verbatim: chapter.title)
                        .retainStyle(RetainTypography.chapterEntry)
                        .foregroundStyle(RetainPalette.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if chapter.hasMarker {
                        RetainStatusDot(colour: RetainPalette.amber, diameter: RetainMetrics.statusDotSmall)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    }
                }
                .padding(.leading, RetainMetrics.leftRuleGapRail)
                .padding(isFirst ? RetainMetrics.chapterRowFirst : RetainMetrics.chapterRowLater)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(RetainSurfaceButtonStyle())
        .padding(.top, isFirst ? 0 : RetainMetrics.chapterRowLaterTopGap)
    }
}
