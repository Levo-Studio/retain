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

/// "New course": a name, the term it is in, and one of exactly four colours.
struct NewCourseDialog: View {

    let terms: [Term]
    @State var draft: CourseDraft

    let create: (CourseDraft) -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "New", comment: "Uppercase label above the new-course dialog title"),
            title: String(localized: "New course", comment: "New-course dialog title, and the button that opens it"),
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
                            text: String(localized: "Term", comment: "Field label for a term, and the label above the name-term dialog title")
                        )
                        termPicker
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
                    confirmTitle: String(localized: "Create", comment: "New-course dialog button that creates the course"),
                    isConfirmEnabled: draft.isSaveable,
                    cancel: cancel,
                    confirm: { create(draft) }
                )
            }
        )
    }

    // MARK: -

    private var termPicker: some View {
        RetainPickerField(
            selection: Binding(
                get: { draft.termID ?? terms.first?.id ?? 0 },
                set: { draft.termID = $0 }
            ),
            options: terms.compactMap(\.id),
            title: { id in terms.first { $0.id == id }?.title ?? "" }
        ) {
            Text(terms.first { $0.id == draft.termID }?.title ?? "")
                .retainStyle(RetainTypography.fieldText)
                .foregroundStyle(RetainPalette.inkPrimary)
                .lineLimit(1)
        }
        .disabled(terms.isEmpty)
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
