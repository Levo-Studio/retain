import SwiftUI

/// What the library shows while there is something in the search field.
///
/// **The export draws the field and no result state for it.** So this is built
/// out of the two shapes board 05 already draws and nothing else: a group is
/// headed the way a course is headed, and a hit is a row on the table's own
/// grid. Nothing new is invented to hold them.
///
/// Every row is a recording and a second inside it, which is what makes the
/// search worth having — it does not find a lecture, it finds the moment.
struct SearchResultsList: View {

    let model: LibraryModel

    var body: some View {
        Group {
            if model.results.isEmpty {
                Text(verbatim: LibraryCopy.noResults)
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .padding(RetainMetrics.libraryCourseHeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.results) { group in
                            heading(group)

                            ForEach(Array(group.hits.enumerated()), id: \.element.id) { index, hit in
                                HitRow(hit: hit, isLast: index == group.hits.count - 1) {
                                    Task { await model.open(hit) }
                                }
                                .padding(RetainMetrics.libraryBody)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The same heading the course gets: the recording's name, then what it
    /// belongs to. A recording with no topic is headed by when it happened,
    /// exactly as the table's Topic column has it.
    private func heading(_ group: SearchResultGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.libraryCourseHeadingGap) {
            Text(verbatim: title(of: group))
                .retainStyle(RetainTypography.libraryCourseHeading)
                .foregroundStyle(RetainPalette.inkPrimary)
                .lineLimit(1)

            Text(verbatim: group.courseName)
                .retainStyle(RetainTypography.libraryCourseSubtitle)
                .foregroundStyle(RetainPalette.inkLabel)

            Spacer(minLength: 0)
        }
        .padding(RetainMetrics.libraryCourseHeading)
    }

    private func title(of group: SearchResultGroup) -> String {
        if let topic = group.topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topic
        }
        return group.startedAt.formatted(.dateTime.day().month(.wide).year().hour().minute())
    }
}

// MARK: - One hit

struct HitRow: View {

    let hit: SearchHit
    let isLast: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            RecordingTableColumns {
                Text(verbatim: SearchResults.snippet(of: hit))
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkBodyStrong)
                    .lineLimit(1)

                Text(verbatim: RetainTimeFormat.clock(hit.time))
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkBody)

                Text(verbatim: SearchResults.label(for: hit.source))
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkLabel)

                Color.clear.frame(height: 0)
            }
            .padding(RetainMetrics.tableRow)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(RetainPalette.lineTableRowSeparator).frame(height: 1) }
            }
        }
        .buttonStyle(RetainSurfaceButtonStyle())
    }
}
