import SwiftUI

nonisolated extension CourseColor {

    /// The drawn colour for a stored index.
    ///
    /// The database keeps the index and the design keeps the value, which is
    /// what lets the export be refreshed without touching a single row.
    var swatch: Color {
        let colours = RetainPalette.courseColours
        guard colours.indices.contains(rawValue) else { return RetainPalette.accent }
        return colours[rawValue]
    }
}

// MARK: -

/// "New course": a name, the terms it runs in, and one of exactly four colours.
struct CourseDialog: View {

    let terms: [Term]
    @State var draft: CourseDraft

    let confirm: (CourseDraft) -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: draft.isEditing
                ? String(localized: "Course", comment: "Uppercase label above the edit-course dialog title")
                : String(localized: "New", comment: "Uppercase label above the new-course dialog title"),
            title: draft.isEditing
                ? String(localized: "Edit course", comment: "Edit-course dialog title, and the action that opens it")
                : String(localized: "New course", comment: "New-course dialog title, and the button that opens it"),
            content: {
                DialogForm {
                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Name", comment: "New-course dialog field label")
                        )
                        RetainTextField(placeholder: "", text: $draft.name)
                    }

                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Terms", comment: "New-course dialog field label above the terms a course runs in")
                        )
                        termsField
                    }

                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Colour", comment: "New-course dialog field label for the colour picker")
                        )
                        colours
                    }
                }
            },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Cancel", comment: "Dialog button that closes without saving"),
                    confirmTitle: draft.isEditing
                        ? String(localized: "Save", comment: "Dialog button that writes what was edited")
                        : String(localized: "Create", comment: "New-course dialog button that creates the course"),
                    isConfirmEnabled: draft.isSaveable,
                    cancel: cancel,
                    confirm: { confirm(draft) }
                )
            }
        )
    }

    // MARK: -

    /// The terms the course runs in — **several of them**, which board 07 does
    /// not draw.
    ///
    /// The export draws a single-select picker field here, from when a course
    /// belonged to exactly one term. It belongs to as many as the user has it
    /// in, so a field that opens a menu and closes on one answer is the wrong
    /// shape: every term a person has is worth seeing at once, and each is
    /// simply on or off.
    ///
    /// Nothing new is drawn for it. Each term is `RetainSegment` — board 03's
    /// segment, which is the export's own way of saying "these sit beside each
    /// other and this one is chosen" — laid out by `RetainWrappingRow` so that
    /// a year's worth of terms goes onto a second line instead of scrolling or
    /// being cut off inside a 430-point sheet. The one thing that is not drawn
    /// anywhere is that several can be on at once.
    @ViewBuilder
    private var termsField: some View {
        if terms.isEmpty {
            // Not an empty box. Create is already refused without a term, and a
            // blank row leaves the reader working out why on their own.
            Text(String(localized: "Name a term first — a course runs in one.",
                        comment: "The new-course dialog's term row on an install with no terms yet"))
                .retainStyle(RetainTypography.fieldText)
                .foregroundStyle(RetainPalette.inkLabel)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            RetainWrappingRow(
                spacing: RetainMetrics.segmentGap,
                rowSpacing: RetainMetrics.segmentGap
            ) {
                ForEach(terms) { term in
                    if let id = term.id {
                        RetainSegment(
                            title: term.title,
                            isSelected: draft.termIDs.contains(id),
                            select: { draft.toggle(id) }
                        )
                    }
                }
            }
        }
    }

    private var colours: some View {
        HStack(spacing: RetainMetrics.dialogColourSwatchGap) {
            ForEach(CourseColor.offered, id: \.self) { colour in
                Button {
                    draft.color = colour
                } label: {
                    RetainColourSwatch(colour: colour.swatch, isSelected: draft.color == colour)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(colour.name))
            }
            Spacer(minLength: 0)
        }
    }
}
