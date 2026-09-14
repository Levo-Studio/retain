import SwiftUI

/// The General section — **the one nothing draws.**
///
/// The written brief puts one decision here that the export has no board for: a
/// term is either a half-year or a semester, the user picks which, and then
/// sets which courses they have in it. Everything below is therefore invented,
/// and it is invented out of parts the export already has rather than out of
/// taste: the settings form of board 06, the segment pair of board 03, and the
/// course row of board 05 — colour rail, name, recording count.
struct GeneralPane: View {

    @Bindable var model: SettingsModel

    /// Which dialog is open over the window, if any.
    @Binding var sheet: LibrarySheet?

    var body: some View {
        SettingsPaneSection(
            section: .general,
            title: String(localized: "General", comment: "Settings section heading and sidebar row"),
            description: String(
                localized: "A term is the stretch of time the library is filtered by. Pick what yours are called and which courses they hold.",
                comment: "Settings section description under the general heading"
            ),
            isFirst: true
        ) {
            SettingsForm {
                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Term", comment: "Field label for a term, and the label above the name-term dialog title")
                    )
                    termRow
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Kind", comment: "Field label for half-year or semester")
                    )
                    kindRow
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Courses", comment: "Settings field label for the course list")
                    )
                    courseList
                }
            }
        }
        .task { await model.loadLibrary() }
        .onChange(of: model.selectedTermID) { _, _ in
            Task { await model.loadCourses() }
        }
    }

    // MARK: - Term

    private var termRow: some View {
        HStack(spacing: RetainMetrics.settingsModelRowGap) {
            RetainPickerField(
                selection: Binding(
                    get: { model.selectedTermID ?? 0 },
                    set: { model.selectedTermID = $0 }
                ),
                options: model.terms.compactMap(\.id),
                title: { id in model.terms.first { $0.id == id }?.title ?? "" }
            ) {
                Text(model.selectedTerm?.title ?? noTerms)
                    .retainStyle(RetainTypography.fieldText)
                    .foregroundStyle(model.selectedTerm == nil ? RetainPalette.inkLabel : RetainPalette.inkPrimary)
                    .lineLimit(1)
            }
            .disabled(model.terms.isEmpty)

            Button {
                sheet = .nameTerm(model.selectedTerm)
            } label: {
                Text(model.selectedTerm == nil ? newTermTitle : renameTitle)
            }
            .buttonStyle(inlineButton)
            .fixedSize()
        }
    }

    private var kindRow: some View {
        TermKindSegments(
            kind: Binding(
                get: { model.selectedTerm?.kind ?? .halfYear },
                set: { kind in Task { await model.setTermKind(kind) } }
            )
        )
        .disabled(model.selectedTerm == nil)
        .opacity(model.selectedTerm == nil ? RetainInteraction.disabledOpacity : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Courses

    private var courseList: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.sidebarRowGap) {
            ForEach(model.courses) { listing in
                courseRow(listing)
            }

            Button {
                sheet = .newCourse(model.selectedTermID)
            } label: {
                // The `+` is the glyph the export draws in front of the label,
                // not part of it: "+ New course" as a key would generate the
                // same Swift symbol as the dialog's own "New course" title.
                Text(verbatim: RetainGlyph.add + " ")
                    + Text("New course", comment: "New-course dialog title, and the button that opens it")
            }
            .buttonStyle(inlineButton)
            .disabled(model.selectedTermID == nil)
            .fixedSize()
            .padding(.top, model.courses.isEmpty ? 0 : RetainMetrics.sidebarRowGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The library sidebar's own row: a colour rail, the name, the count —
    /// and, here, the way back into it.
    ///
    /// The term row above has "Rename" for the same reason and the export draws
    /// it; a course had nothing, so its name and the terms it runs in were
    /// settled the moment it was created and never again.
    private func courseRow(_ listing: CourseListing) -> some View {
        HStack(spacing: RetainMetrics.settingsModelRowGap) {
            RoundedRectangle(cornerRadius: RetainMetrics.radiusCourseColourRail)
                .fill(listing.course.color.swatch)
                .frame(
                    width: RetainMetrics.courseColourRail.width,
                    height: RetainMetrics.courseColourRail.height
                )

            Text(listing.course.name)
                .retainStyle(RetainTypography.sidebarRow)
                .foregroundStyle(RetainPalette.inkBody)

            Spacer(minLength: 0)

            Text(listing.recordingCount.formatted())
                .retainStyle(RetainTypography.librarySidebarCount)
                .foregroundStyle(RetainPalette.inkLabel)

            Button {
                Task { await openEditor(for: listing.course) }
            } label: {
                Text(editTitle)
            }
            .buttonStyle(inlineButton)
            .fixedSize()
        }
        .padding(RetainMetrics.sidebarRowLibrary)
    }

    /// Reads which terms the course runs in before opening the dialog, so its
    /// chips arrive already ticked rather than filling in a frame later.
    private func openEditor(for course: Course) async {
        guard let library = model.library, let id = course.id else { return }
        let termIDs = Set((try? await library.terms(of: id))?.compactMap(\.id) ?? [])
        sheet = .editCourse(course, termIDs: termIDs)
    }

    // MARK: -

    private var inlineButton: RetainSecondaryButtonStyle {
        RetainSecondaryButtonStyle(
            textStyle: RetainTypography.fieldLabelSettings,
            padding: RetainMetrics.settingsInlineButtonPadding,
            cornerRadius: RetainMetrics.radiusTextField,
            isFilled: true
        )
    }

    private var noTerms: String {
        String(localized: "No term yet", comment: "Term picker label before the first term has been named")
    }

    private var newTermTitle: String {
        String(localized: "New term", comment: "Button that creates the first term")
    }

    private var editTitle: String {
        String(localized: "Edit", comment: "Action beside a course that opens the edit-course dialog")
    }

    private var renameTitle: String {
        String(localized: "Rename", comment: "Button that opens the name-term dialog for the selected term")
    }
}
