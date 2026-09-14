import SwiftUI

// MARK: - The card

/// The 430-point sheet every modal window in Retain is drawn on.
///
/// Board 07 draws four of them and its own heading says why they are one type:
/// "all modal windows in the same style". They differ in two ways and no
/// others — whether the header carries a status dot, and whether a rule
/// separates the header from a form.
struct RetainDialog<Content: View, Footer: View>: View {

    /// The uppercase label above the title.
    let label: String

    /// The dot in front of that label, where a dialog has one. Only the
    /// "No connection" dialog does.
    var labelDot: Color?

    /// The label's own ink, which the "No connection" dialog paints red.
    var labelInk: Color = RetainPalette.inkLabel

    let title: String

    /// The paragraph under the title, for the dialogs that have one instead of
    /// a form.
    var message: (() -> Text)?

    /// The form, for the dialogs that have one instead of a paragraph. Its
    /// presence is what puts the rule under the header.
    @ViewBuilder let content: () -> Content

    @ViewBuilder let footer: () -> Footer

    private var hasForm: Bool { Content.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if hasForm {
                Rectangle()
                    .fill(RetainPalette.lineDivider)
                    .frame(height: RetainMetrics.borderWidth)

                content()
                    .padding(RetainMetrics.dialogBody)
            }

            HStack(spacing: RetainMetrics.dialogFooterGap) {
                Spacer(minLength: 0)
                footer()
            }
            .padding(hasForm ? RetainMetrics.dialogFooterAfterForm : RetainMetrics.dialogFooter)
        }
        .frame(width: RetainMetrics.dialogWidth)
        .background(RetainPalette.surfaceWindow)
        .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusDialog))
        .overlay {
            RoundedRectangle(cornerRadius: RetainMetrics.radiusDialog)
                .strokeBorder(RetainPalette.lineWindowBorder, lineWidth: RetainMetrics.borderWidth)
        }
        .shadow(
            color: RetainMetrics.dialogShadow.color,
            radius: RetainMetrics.dialogShadow.radius,
            y: RetainMetrics.dialogShadow.offsetY
        )
    }

    // MARK: -

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelRow

            Text(title)
                .retainStyle(RetainTypography.dialogTitle)
                .foregroundStyle(RetainPalette.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, labelDot == nil
                         ? RetainMetrics.dialogLabelTitleGap
                         : RetainMetrics.dialogStatusLabelTitleGap)

            if let message {
                message()
                    .retainStyle(RetainTypography.dialogBody)
                    .foregroundStyle(RetainPalette.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RetainMetrics.dialogTitleBodyGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(hasForm ? RetainMetrics.dialogHeaderWithRule : RetainMetrics.dialogHeader)
    }

    @ViewBuilder
    private var labelRow: some View {
        if let labelDot {
            HStack(spacing: RetainMetrics.dialogStatusRowGap) {
                RetainStatusDot(colour: labelDot, diameter: RetainMetrics.statusDotDialog)
                labelText
            }
        } else {
            labelText
        }
    }

    private var labelText: some View {
        Text(label)
            .retainStyle(RetainTypography.uppercaseLabel)
            .foregroundStyle(labelInk)
    }
}

// MARK: - Convenience

extension RetainDialog where Content == EmptyView {

    /// A dialog whose body is a paragraph rather than a form.
    init(
        label: String,
        labelDot: Color? = nil,
        labelInk: Color = RetainPalette.inkLabel,
        title: String,
        message: @escaping () -> Text,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            label: label,
            labelDot: labelDot,
            labelInk: labelInk,
            title: title,
            message: message,
            content: { EmptyView() },
            footer: footer
        )
    }
}

// MARK: - The form inside one

/// The dialog's two-column form: a 104-point label column, the value beside it.
struct DialogForm<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: RetainMetrics.dialogForm.columnGap,
            verticalSpacing: RetainMetrics.dialogForm.rowGap
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The left-hand cell of a dialog form row. Lighter than the settings one — the
/// export sets it at 400 rather than 500.
struct DialogFieldLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .retainStyle(RetainTypography.fieldLabelDialog)
            .foregroundStyle(RetainPalette.inkBody)
            .frame(width: RetainMetrics.dialogForm.labelColumn, alignment: .leading)
    }
}

// MARK: - The two buttons

/// The right-aligned pair every dialog footer ends in.
struct DialogButtons: View {

    let cancelTitle: String
    let confirmTitle: String
    var isConfirmEnabled = true
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        Group {
            Button(cancelTitle, action: cancel)
                .buttonStyle(RetainSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button(confirmTitle, action: confirm)
                .buttonStyle(RetainPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isConfirmEnabled)
        }
    }
}
