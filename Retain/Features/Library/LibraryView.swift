import SwiftUI

/// Board 05: terms in the title bar, courses in the sidebar, recordings in a
/// table.
struct LibraryView: View {

    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                LibrarySidebar(model: model)
                    .frame(width: RetainMetrics.librarySidebarWidth)

                RetainDivider(axis: .vertical)

                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .background(RetainPalette.surfaceWindow)
        .task { await model.load() }
    }

    // MARK: - The term picker

    private var titleBar: some View {
        RetainTitleBar(title: LibraryCopy.windowTitle) {
            Menu {
                ForEach(model.terms) { term in
                    Button(term.title) {
                        Task { await model.select(term: term) }
                    }
                }
            } label: {
                HStack(spacing: RetainMetrics.titleBarPillGap) {
                    Circle()
                        .fill(RetainPalette.accent)
                        .frame(width: RetainMetrics.statusDotSmall, height: RetainMetrics.statusDotSmall)

                    Text(verbatim: model.selectedTerm?.title ?? LibraryCopy.noTerms)
                        .retainStyle(RetainTypography.titleBarTermPill)
                        .foregroundStyle(RetainPalette.inkPrimary)

                    Text(verbatim: "▾")
                        .retainStyle(RetainTypography.chevron)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
                .padding(RetainMetrics.titleBarPillPadding)
                .background {
                    RoundedRectangle(cornerRadius: RetainMetrics.radiusStatusPill, style: .continuous)
                        .fill(RetainPalette.surfaceInsetControl)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: RetainMetrics.radiusStatusPill, style: .continuous)
                        .strokeBorder(RetainPalette.lineControlBorder, lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Search, then either the table or the results

    private var main: some View {
        VStack(spacing: 0) {
            header

            if model.isShowingResults {
                SearchResultsList(model: model)
            } else {
                RecordingTable(model: model)
            }
        }
    }

    private var header: some View {
        HStack(spacing: RetainMetrics.libraryHeaderGap) {
            TextField(text: $model.query) {
                Text(verbatim: LibraryCopy.searchPlaceholder)
            }
            .textFieldStyle(.plain)
            .retainStyle(RetainTypography.fieldText)
            .foregroundStyle(RetainPalette.inkPrimary)
            .padding(RetainMetrics.searchFieldPadding)
            .background {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusSearchField, style: .continuous)
                    .fill(RetainPalette.surfaceInsetControl)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusSearchField, style: .continuous)
                    .strokeBorder(
                        model.query.isEmpty ? RetainPalette.lineControlBorder : RetainInteraction.focusBorder,
                        lineWidth: 1
                    )
            }

            // The export draws one order and names it. There is no second one
            // to offer, so this says what the order is rather than pretending
            // to be a choice.
            Text(verbatim: LibraryCopy.sortByDate + " ▾")
                .retainStyle(RetainTypography.librarySortControl)
                .foregroundStyle(RetainPalette.inkLabel)
        }
        .padding(RetainMetrics.libraryHeader)
        .overlay(alignment: .bottom) { RetainDivider() }
    }
}

// MARK: - Courses

/// The sidebar: which term, and the courses in it.
struct LibrarySidebar: View {

    let model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.sidebarRowGap) {
            termHeader

            if model.courses.isEmpty {
                Text(verbatim: LibraryCopy.noCourses)
                    .retainStyle(RetainTypography.librarySidebarCount)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .padding(RetainMetrics.sidebarRowLibrary)
            } else {
                ForEach(model.courses) { listing in
                    CourseRow(listing: listing, isSelected: listing.id == model.selectedCourse?.id) {
                        Task { await model.select(course: listing) }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                model.onNewCourse?()
            } label: {
                Text(verbatim: LibraryCopy.newCourse)
                    .retainStyle(RetainTypography.librarySidebarNewCourse)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RetainMetrics.librarySidebarNewCoursePadding)
            }
            .buttonStyle(RetainSurfaceButtonStyle(cornerRadius: RetainMetrics.radiusSidebarRow))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(RetainMetrics.sidebarPadding)
        .background(RetainPalette.surfaceRail)
    }

    private var termHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.librarySidebarRowGap) {
            VStack(alignment: .leading, spacing: RetainMetrics.librarySidebarTermSubtitleGap) {
                Text(verbatim: model.selectedTerm?.title ?? LibraryCopy.noTerms)
                    .retainStyle(RetainTypography.librarySidebarTermTitle)
                    .foregroundStyle(RetainPalette.inkPrimary)

                Text(verbatim: model.termSubtitle)
                    .retainStyle(RetainTypography.librarySidebarTermSubtitle)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let term = model.selectedTerm {
                Button {
                    model.onRenameTerm?(term)
                } label: {
                    Text(verbatim: LibraryCopy.rename)
                        .retainStyle(RetainTypography.librarySidebarAction)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
                .buttonStyle(RetainSurfaceButtonStyle())
            }
        }
        .padding(RetainMetrics.librarySidebarTermHeader)
    }
}

/// One course: its colour, its name, and how many recordings are in it.
struct CourseRow: View {

    let listing: CourseListing
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: RetainMetrics.librarySidebarRowGap) {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusCourseColourRail, style: .continuous)
                    .fill(RetainPalette.courseColours[listing.course.color.rawValue])
                    .frame(
                        width: RetainMetrics.courseColourRail.width,
                        height: RetainMetrics.courseColourRail.height
                    )

                Text(verbatim: listing.course.name)
                    .retainStyle(RetainTypography.sidebarRow)
                    .foregroundStyle(isSelected ? RetainPalette.inkPrimary : RetainPalette.inkBody)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: listing.recordingCount.formatted())
                    .retainStyle(RetainTypography.librarySidebarCount)
                    .foregroundStyle(RetainPalette.inkLabel)
            }
            .padding(RetainMetrics.sidebarRowLibrary)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            RetainSurfaceButtonStyle(
                resting: isSelected ? RetainPalette.selectedRowSwatch : nil,
                cornerRadius: RetainMetrics.radiusSidebarRow
            )
        )
    }
}
