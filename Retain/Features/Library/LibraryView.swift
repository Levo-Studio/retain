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
        .task { await model.follow() }
        .libraryEditingSheet(
            $model.sheet,
            terms: model.terms,
            library: model.libraryRepository,
            reload: { await model.reloadAfterEditing() }
        )
    }

    // MARK: - The term picker

    /// Choosing a term goes through the model, which reloads the courses under
    /// it and remembers the choice for the next time the window opens.
    private var termBinding: Binding<Term> {
        Binding(
            get: { model.selectedTerm ?? model.terms.first ?? Term(title: "") },
            set: { term in Task { await model.select(term: term) } }
        )
    }

    private var titleBar: some View {
        RetainTitleBar(
            title: LibraryCopy.windowTitle,
            // The sidebar's own edge: its padding plus a row's. That is where
            // the term, the courses and "New course" all begin.
            titleLeading: RetainMetrics.sidebarPadding.leading + RetainMetrics.sidebarRowLibrary.leading
        ) {
            ModelStatusPill()

            recordButton

            // The same picker the settings boards draw, in the box this title
            // bar draws it in: a rounder corner and tighter padding, with the
            // accent dot in front of the name.
            RetainPickerField(
                selection: termBinding,
                options: model.terms,
                title: \.title,
                cornerRadius: RetainMetrics.radiusStatusPill,
                padding: RetainMetrics.titleBarPillPadding
            ) {
                HStack(spacing: RetainMetrics.titleBarPillGap) {
                    RetainStatusDot(colour: RetainPalette.accent, diameter: RetainMetrics.statusDotSmall)

                    Text(verbatim: model.selectedTerm?.title ?? LibraryCopy.noTerms)
                        .retainStyle(RetainTypography.titleBarTermPill)
                        .foregroundStyle(RetainPalette.inkPrimary)
                        .fixedSize()
                }
                .padding(.trailing, RetainMetrics.titleBarPillGap)
            }
            .fixedSize()
            .contextMenu {
                // The library is where somebody goes looking for an old
                // half-year, so it is where they decide they are done with it.
                // Creating and renaming a term still live in Settings; this is
                // the one action that is about a term you are already looking
                // at.
                if let selected = model.selectedTerm {
                    Button(LibraryCopy.deleteTerm) {
                        Task { await model.confirmDeletion(of: selected) }
                    }
                }
            }
        }
    }

    /// Starts a recording for the course in the sidebar, without going back to
    /// the menu bar to pick the same course a second time.
    ///
    /// Not on board 05, which draws the library as a place to read what was
    /// already recorded. It is here because the library is where somebody sits
    /// with the course they are about to be taught open in front of them, and
    /// the alternative was the status item, a second picker, and the same
    /// choice made twice.
    ///
    /// The red outline is the mark Retain gives a control that starts or ends a
    /// recording — the same one board 02 draws on "Stop" and "Finish".
    private var recordButton: some View {
        // One button, two states. While a lecture is running it says Finish and
        // ends it — the library is the app's home window and somebody sitting
        // in it during a lesson should not have to go and find the recording
        // window to stop the microphone.
        Button {
            if model.isLectureRunning {
                model.finish()
            } else {
                model.record()
            }
        } label: {
            HStack(spacing: RetainMetrics.titleBarPillGap) {
                RetainStatusDot(
                    colour: RetainPalette.redRecording,
                    diameter: RetainMetrics.statusDotSmall,
                    loop: model.isLectureRunning ? .recordingPulse : nil
                )

                Text(verbatim: model.isLectureRunning ? LibraryCopy.finish : LibraryCopy.record)
            }
        }
        .buttonStyle(
            RetainSecondaryButtonStyle(
                textStyle: RetainTypography.titleBarButton,
                padding: RetainMetrics.titleBarButtonPadding,
                cornerRadius: RetainMetrics.radiusExportButton,
                isFilled: true,
                ink: RetainPalette.redInk,
                border: RetainPalette.redBorderSwatch
            )
        )
        .disabled(model.isLectureRunning ? false : !model.isRecordable)
        .fixedSize()
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
            RetainTextField(
                placeholder: LibraryCopy.searchPlaceholder,
                text: $model.query,
                cornerRadius: RetainMetrics.radiusSearchField,
                padding: RetainMetrics.searchFieldPadding
            )

            // The export draws one order and names it. There is no second one
            // to offer, so this says what the order is rather than pretending
            // to be a choice.
            Text(verbatim: LibraryCopy.sortByDate + " " + RetainGlyph.disclosure)
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
                    // Right-click rather than a button on the row: board 05
                    // draws the course rows as a colour rail, a name and a
                    // count, with no action in them, and a visible control
                    // there would be chrome the export does not have. Settings'
                    // General pane carries the same action where the term row
                    // beside it already carries "Rename".
                    .contextMenu {
                        Button(LibraryCopy.editCourse) {
                            Task { await model.edit(listing.course) }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                model.sheet = .newCourse(model.selectedTerm?.id)
            } label: {
                Text(verbatim: RetainGlyph.add + " " + LibraryCopy.newCourse)
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
                    model.sheet = .nameTerm(term)
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
