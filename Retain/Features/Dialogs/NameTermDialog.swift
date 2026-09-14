import SwiftUI

/// "Name term": a title, a period at month granularity, what kind of term it
/// is, and whether it is the current one.
struct NameTermDialog: View {

    /// Every term there is, so the dialog can say which one would stop being
    /// current.
    let terms: [Term]

    @State var draft: TermDraft

    let save: (TermDraft) -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Term", comment: "Field label for a term, and the label above the name-term dialog title"),
            title: String(localized: "Name term", comment: "Name-term dialog title"),
            content: {
                DialogForm {
                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Title", comment: "Name-term dialog field label")
                        )
                        RetainTextField(placeholder: "", text: $draft.title)
                    }

                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Period", comment: "Name-term dialog field label for the two months")
                        )
                        period
                    }

                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Kind", comment: "Field label for half-year or semester")
                        )
                        kind
                    }

                    GridRow {
                        DialogFieldLabel(
                            text: String(localized: "Current", comment: "Name-term dialog field label, and the toggle's accessibility label")
                        )
                        current
                    }
                }
            },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Cancel", comment: "Dialog button that closes without saving"),
                    confirmTitle: String(localized: "Save", comment: "Name-term dialog button that saves the term"),
                    isConfirmEnabled: draft.isSaveable,
                    cancel: cancel,
                    confirm: { save(draft) }
                )
            }
        )
    }

    // MARK: - Period

    private var period: some View {
        HStack(spacing: RetainMetrics.dialogPeriodFieldGap) {
            monthField($draft.startsOn)
            monthField($draft.endsOn)
        }
    }

    /// One of the two month fields, either of which may be left empty.
    ///
    /// The export draws both filled and offers no way to empty one, because it
    /// was drawn when a period was required. It is not any more, so the menu
    /// carries "No month" ahead of the months and an empty field draws that
    /// word in placeholder ink — the same treatment `RetainTextField` gives an
    /// empty field. Nothing else about the box changes: same chrome, same plain
    /// look with no disclosure, exactly as drawn.
    private func monthField(_ month: Binding<Date?>) -> some View {
        // Around what is in the field, or around today for an empty one: the
        // run of months has to start somewhere, and the month somebody is
        // filling the field in is the likeliest place. "No month" leads,
        // because a field that cannot be emptied again is a field that traps
        // the first date somebody picks by accident.
        let options: [Date?] = [nil]
            + TermMonth.choices(around: month.wrappedValue ?? .now).map(Optional.some)

        return RetainPickerField(
            selection: month,
            options: options,
            title: { $0.map(TermMonth.label) ?? TermMonth.noMonth },
            showsDisclosure: false
        ) {
            Text(month.wrappedValue.map(TermMonth.label) ?? TermMonth.noMonth)
                .retainStyle(RetainTypography.fieldText)
                .foregroundStyle(month.wrappedValue == nil
                                 ? RetainPalette.inkLabel
                                 : RetainPalette.inkPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Kind

    private var kind: some View {
        TermKindSegments(kind: $draft.kind)
    }

    // MARK: - Current

    /// At most one term is current, and the database is what enforces it — a
    /// second one fails the partial unique index rather than quietly winning.
    /// The dialog says which term would be displaced before the switch is
    /// thrown, because "current" is what the library opens on.
    private var current: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.transcriptLabelGapMain) {
            HStack(spacing: RetainMetrics.dialogToggleRowGap) {
                Toggle(isOn: $draft.isCurrent) {
                    Text("Current", comment: "Name-term dialog field label, and the toggle's accessibility label")
                }
                .labelsHidden()
                .toggleStyle(RetainToggleStyle())

                Text(caption)
                    .retainStyle(RetainTypography.toggleCaption)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var caption: String {
        if let displaced = CurrentTerm.displaced(by: draft, among: terms) {
            return CurrentTerm.warning(displacing: displaced)
        }
        return CurrentTerm.caption
    }
}
