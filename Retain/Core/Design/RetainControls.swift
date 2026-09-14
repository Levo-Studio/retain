import SwiftUI

// MARK: - Widths the export draws once

nonisolated extension RetainMetrics {

    /// Every border in the export is one pixel. Written down once rather than
    /// as a `1` at forty call sites, so the day a border gets thicker there is
    /// one place to change.
    static let borderWidth: CGFloat = 1
}

// MARK: - Glyphs

/// Glyphs the export draws as characters rather than as shapes.
///
/// Not copy: nothing here is translated, and nothing here is read aloud — every
/// use is `accessibilityHidden`, because the control around it already says
/// what it does.
nonisolated enum RetainGlyph {

    /// The picker chevron. The export writes `▾` at 10px regular, not a
    /// `chevron.down` symbol, and a symbol would sit on a different baseline
    /// and a different optical weight.
    static let disclosure = "▾"

    /// The `+` in front of "New course". The export draws it as part of the
    /// button's text, one space in front of the label.
    static let add = "+"
}

// MARK: - Field chrome

/// The inset-control box: fill, border and padding.
///
/// Drawn identically on every board that has a field — the settings form, the
/// dialog form, the search fields — so it is one modifier rather than four
/// copies of three values.
struct RetainFieldChrome: ViewModifier {

    /// A field the keyboard is in. The export draws a field with content or
    /// focus at the emphasised border (`#2f353c`) and one at rest at the plain
    /// one; `RetainInteraction` is where that decision is kept.
    var isFocused = false

    var cornerRadius: CGFloat = RetainMetrics.radiusTextField
    var padding: EdgeInsets = RetainMetrics.fieldPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RetainPalette.surfaceInsetControl, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? RetainInteraction.focusBorder : RetainPalette.lineControlBorder,
                        lineWidth: isFocused ? RetainInteraction.focusBorderWidth : RetainMetrics.borderWidth
                    )
            }
    }
}

extension View {

    func retainFieldChrome(
        isFocused: Bool = false,
        cornerRadius: CGFloat = RetainMetrics.radiusTextField,
        padding: EdgeInsets = RetainMetrics.fieldPadding
    ) -> some View {
        modifier(RetainFieldChrome(isFocused: isFocused, cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Text field

/// A one-line field drawn the way the export draws one.
///
/// SwiftUI's own placeholder is painted in a system secondary colour that
/// cannot be set, and the export gives placeholders their own ink (`#7c838c`),
/// so the placeholder is drawn here instead of handed to `TextField`.
struct RetainTextField: View {

    let placeholder: String
    @Binding var text: String

    /// A field whose content must never be drawn as characters — the API key.
    var isSecure = false

    /// The search fields are not form fields: the export draws them rounder
    /// (9 rather than 8) and, in a rail, tighter. The chrome is otherwise the
    /// same box.
    var cornerRadius: CGFloat = RetainMetrics.radiusTextField
    var padding: EdgeInsets = RetainMetrics.fieldPadding

    /// The find bar and the library search read what is typed as it is typed,
    /// so they set their own text style rather than the form's.
    var textStyle: RetainTextStyle = RetainTypography.fieldText

    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .retainStyle(textStyle)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .allowsHitTesting(false)
            }

            field
                .textFieldStyle(.plain)
                .retainStyle(textStyle)
                .foregroundStyle(RetainPalette.inkPrimary)
                .tint(RetainPalette.accent)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .retainFieldChrome(isFocused: focused, cornerRadius: cornerRadius, padding: padding)
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }

    /// Built with an empty `Label` rather than an empty title: a `""` title is
    /// a string catalog key, and an empty key in the catalog is a key nobody
    /// can translate or delete.
    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(text: $text) { EmptyView() }
        } else {
            TextField(text: $text) { EmptyView() }
        }
    }
}

// MARK: - Picker field

/// A field that opens a menu: the model picker, the input picker, the term
/// picker in the new-course dialog.
///
/// A `Menu` in a box rather than SwiftUI's `Picker`, because every `Picker`
/// style on macOS draws its own chrome — an `NSPopUpButton`'s bezel, arrows and
/// system accent — and none of it is what the export draws.
struct RetainPickerField<Value: Hashable, Label: View>: View {

    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    /// The `▾` at the trailing edge. The export draws it on the model picker,
    /// the input picker and the term picker, and **not** on the two month
    /// fields of a term's period, which it paints as plain boxes.
    var showsDisclosure = true

    /// The library's term picker is the same control in a different box: the
    /// same fill and border, a rounder corner and tighter padding, because it
    /// sits in a 38-point title bar rather than in a form.
    var cornerRadius: CGFloat = RetainMetrics.radiusTextField
    var padding: EdgeInsets = RetainMetrics.fieldPadding

    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection = option }
            }
        } label: {
            HStack(spacing: 0) {
                label()
                Spacer(minLength: 0)
                if showsDisclosure {
                    Text(verbatim: RetainGlyph.disclosure)
                        .retainStyle(RetainTypography.chevron)
                        .foregroundStyle(RetainPalette.inkLabel)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .retainFieldChrome(cornerRadius: cornerRadius, padding: padding)
            .contentShape(.rect)
        }
        // `.button` rather than `.borderlessButton`: the borderless style draws
        // the label itself, keeping the text and dropping everything around it,
        // so the field's fill and border never appear. The button style is then
        // `.plain` so that AppKit adds no bezel of its own on top.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Status dot

/// The filled circle in front of a status line.
struct RetainStatusDot: View {

    let colour: Color
    var diameter: CGFloat = RetainMetrics.statusDotSettings

    /// Set where the export draws the dot breathing — the summarizing state.
    var breathes = false

    /// A loop other than `breathe`, with its own delay: the chat rail's three
    /// typing dots are this same circle on `typingIndicator` at 0, .2 and .4.
    var loop: RetainMotion.Curve?
    var loopDelay: Double = 0

    var body: some View {
        Group {
            if breathes {
                circle.retainLoop(.breathe)
            } else if let loop {
                circle.retainLoop(loop, delay: loopDelay)
            } else {
                circle
            }
        }
        .accessibilityHidden(true)
    }

    private var circle: some View {
        Circle()
            .fill(colour)
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Progress

/// A determinate bar: the speech-model download and the microphone level.
struct RetainProgressTrack: View {

    /// 0…1. Clamped, because a level meter fed a bad sample should not draw
    /// outside its track.
    let fraction: Double

    var height: CGFloat = RetainMetrics.progressBarHeightDownload
    var fill: Color = RetainPalette.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(RetainPalette.lineWindowBorder)
                RoundedRectangle(cornerRadius: RetainMetrics.radiusProgressBar)
                    .fill(fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusProgressBar))
        }
        .frame(height: height)
    }
}

// MARK: - Toggle

/// The 34 × 20 switch the name-term dialog draws.
///
/// The export draws it **on** and never off. On is the accent track with the
/// on-accent knob, exactly as drawn; off is the same track unfilled — the
/// window border, which is also what an unfilled progress track is painted in —
/// with the knob in label ink. Nothing new is introduced, and when the owner
/// draws the off state this is the one place it changes.
struct RetainToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? RetainPalette.accent : RetainPalette.lineWindowBorder)
                .frame(width: RetainMetrics.toggleSize.width, height: RetainMetrics.toggleSize.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? RetainPalette.onAccent : RetainPalette.inkLabel)
                        .frame(
                            width: RetainMetrics.toggleKnobDiameter,
                            height: RetainMetrics.toggleKnobDiameter
                        )
                        .padding(.horizontal, RetainMetrics.toggleInset)
                }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Colour swatch

/// One of the four colours the new-course dialog offers.
struct RetainColourSwatch: View {

    let colour: Color
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: RetainMetrics.radiusColourSwatch)
            .fill(colour)
            .frame(
                width: RetainMetrics.colourSwatchSize.width,
                height: RetainMetrics.colourSwatchSize.height
            )
            .overlay {
                // `outline` in CSS sits outside the box and does not move it.
                // A stroked rounded rectangle inset by the negative offset is
                // the same drawing, and leaves the swatch its 20 points.
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: RetainMetrics.radiusColourSwatch + RetainMetrics.colourSwatchSelectionOffset
                    )
                    .strokeBorder(
                        RetainPalette.inkPrimary,
                        lineWidth: RetainMetrics.colourSwatchSelectionWidth
                    )
                    .padding(-RetainMetrics.colourSwatchSelectionOffset
                             - RetainMetrics.colourSwatchSelectionWidth / 2)
                }
            }
    }
}

// MARK: - Buttons

/// The filled accent button: "Allow access", "Create", "Save", "Try again".
struct RetainPrimaryButtonStyle: ButtonStyle {

    var textStyle: RetainTextStyle = RetainTypography.buttonDialogPrimary
    var padding: EdgeInsets = RetainMetrics.dialogButtonPadding
    var cornerRadius: CGFloat = RetainMetrics.radiusDialogButton

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .retainStyle(textStyle)
            .foregroundStyle(RetainPalette.onAccent)
            .padding(padding)
            .background(fill(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(isEnabled ? 1 : RetainInteraction.disabledOpacity)
            .contentShape(.rect)
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return RetainInteraction.pressed(RetainPalette.accentValue).color }
        // The one hover the export actually draws.
        return hovering && isEnabled ? RetainPalette.accentHover : RetainPalette.accent
    }
}

/// The outlined button beside it: "Later", "Cancel", "Settings".
struct RetainSecondaryButtonStyle: ButtonStyle {

    var textStyle: RetainTextStyle = RetainTypography.buttonDialogSecondary
    var padding: EdgeInsets = RetainMetrics.dialogButtonPadding
    var cornerRadius: CGFloat = RetainMetrics.radiusDialogButton

    /// The settings form's inline buttons sit on the inset fill; the dialog
    /// footer's sit on the dialog body with no fill at all.
    var isFilled = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .retainStyle(textStyle)
            .foregroundStyle(RetainPalette.inkBody)
            .padding(padding)
            .background(fill(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        hovering && isEnabled
                            ? RetainPalette.lineControlBorderEmphasised
                            : RetainPalette.lineControlBorder,
                        lineWidth: RetainMetrics.borderWidth
                    )
            }
            .opacity(isEnabled ? 1 : RetainInteraction.disabledOpacity)
            .contentShape(.rect)
            .onHover { hovering = $0 }
    }

    /// The surface ladder the export already draws, rather than a computed
    /// step: a control at rest sits on the inset fill, a hovered one on the
    /// selected-row fill, a pressed one on the meta-strip fill below it.
    private func fill(pressed: Bool) -> Color {
        guard isFilled else {
            return pressed ? RetainPalette.surfaceInsetControl : .clear
        }
        if pressed { return RetainPalette.surfaceMetaStrip }
        return hovering && isEnabled ? RetainPalette.surfaceSelectedRow : RetainPalette.surfaceInsetControl
    }
}

// MARK: - The accent as a value

nonisolated extension RetainPalette {

    /// The accent on the OKLCH axes rather than as a `Color`.
    ///
    /// `RetainInteraction` steps lightness, and lightness cannot be read back
    /// out of a SwiftUI `Color`. The swatch table is where the palette keeps
    /// the values themselves, and course colour 1 *is* the accent —
    /// `oklch(.78 .13 165)` heads both lists in `docs/design/README.md` — so
    /// this names what is already there instead of writing it down twice.
    static var accentValue: RetainColor {
        courseSwatches.first ?? RetainColor(OKLCH(0.78, 0.13, 165))
    }
}
