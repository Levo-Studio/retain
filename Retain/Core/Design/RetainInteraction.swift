import SwiftUI

/// What a control looks like when it is not just sitting there.
///
/// **The export draws none of this.** Across all seven boards there are exactly
/// two hover colours — accent hover and link hover — and no pressed fill, no
/// focus ring and no disabled control anywhere. Every screen needs all four
/// within its first hour, so they are derived here, once, rather than invented
/// three times in three feature folders.
///
/// Everything below is derived from something the export does draw. Nothing
/// introduces a hue, and the two rules that matter are read straight off the
/// two hover colours the design gives:
///
/// ```
/// accent  oklch(.78 .13 165)  →  hover  oklch(.84 .13 165)   +0.06 lightness
/// blue    oklch(.70 .11 250)  →  hover  oklch(.78 .11 250)   +0.08 lightness
/// ```
///
/// So a hover is **a step up in lightness at unchanged hue and chroma**, and
/// pressed is the same step down. That is the whole system, and it is why this
/// file contains a transform rather than a second palette: a palette would have
/// to be refreshed every time `docs/design/` is, and this cannot fall out of
/// step with it.
///
/// When the owner draws these states, replace the constants here and every
/// control follows. That is the point of them being in one file.
nonisolated enum RetainInteraction {

    /// The lightness step between a colour and its hover, in OKLCH.
    ///
    /// 0.07 rather than 0.06 or 0.08: the export's two examples disagree by
    /// that much, and splitting them keeps both within a hundredth of what was
    /// drawn while giving every other colour one consistent rule.
    static let hoverLightnessStep: Double = 0.07

    /// Pressed goes the same distance the other way. A control that lightens on
    /// hover and lightens further on press reads as broken — the press has to
    /// be the reversal, which is also what makes it feel like a physical one.
    static let pressedLightnessStep: Double = -0.07

    /// A disabled control keeps its colour and loses its presence.
    ///
    /// Opacity rather than a grey fill, because the export has no disabled
    /// grey: inventing one would mean inventing a colour, while fading the real
    /// one is a transform of something drawn. 0.4 is far enough that nothing
    /// invites a click and near enough that the label stays readable, which
    /// matters — a disabled control still has to say what it would do.
    static let disabledOpacity: Double = 0.4

    // MARK: - Applying the step

    static func hovered(_ colour: RetainColor) -> RetainColor {
        stepped(colour, by: hoverLightnessStep)
    }

    static func pressed(_ colour: RetainColor) -> RetainColor {
        stepped(colour, by: pressedLightnessStep)
    }

    /// Moves a colour along the lightness axis, clamped to the range OKLCH
    /// defines. Hue and chroma are untouched, which is what keeps a stepped
    /// accent recognisably the accent.
    ///
    /// One caveat, and it is sRGB's rather than this transform's: a colour that
    /// is already near the edge of the gamut can be pushed out of it by a
    /// lightness step, and the channels are then clamped back in. The red
    /// `oklch(.68 .17 25)` is the one in this palette that does it — hovered,
    /// its red channel wants 1.035 — and the clamp costs it about 0.01 chroma.
    /// That is well under what an eye resolves, so it is accepted rather than
    /// gamut-mapped: proper mapping would mean walking chroma down until the
    /// colour fits, which is a good deal of machinery for one hover state on
    /// one destructive button.
    static func stepped(_ colour: RetainColor, by amount: Double) -> RetainColor {
        // Read back onto the OKLCH axes, move one of them, convert forward
        // again. Nudging the hex channels instead would change hue and chroma
        // along with lightness — an accent that drifts towards grey as it
        // lightens is exactly the tell that a hover was faked.
        let oklch = OKLCH(from: colour)
        return RetainColor(
            OKLCH(min(1, max(0, oklch.lightness + amount)), oklch.chroma, oklch.hue, alpha: oklch.alpha)
        )
    }

    // MARK: - Focus

    /// The ring around whatever the keyboard is on.
    ///
    /// The export draws no focus ring, but it does draw a control border in two
    /// strengths — `#272b31` at rest and `#2f353c` on a field that has content
    /// or is being typed into. That second one is already "this control is the
    /// one you are working in", so focus uses it rather than adding a third
    /// state nobody drew.
    ///
    /// Retain is a keyboard app — the whole reason the shell is an
    /// `NSStatusItem` is that a hotkey can reach it — so focus being visible is
    /// not decoration here.
    static var focusBorder: Color { RetainPalette.lineControlBorderEmphasised }

    /// Width of that border. The export draws every control border at 1px and
    /// every emphasis rule at 2px; focus takes the emphasis width so it reads
    /// at a glance without changing the control's size.
    static let focusBorderWidth: CGFloat = 2

    // MARK: - A highlight the user made

    /// What a passage of the notes looks like once the user has marked it.
    ///
    /// Also not drawn. The export has two marked-text treatments and this is
    /// neither of them: the **term highlight** `oklch(.38 .06 95)` is the
    /// model's emphasis inside a note, and the **search hit**
    /// `oklch(.42 .09 95)` is transient. A user highlight is a third thing —
    /// permanent, and the user's rather than the model's.
    ///
    /// It takes the blue the export already uses for everything the user
    /// themselves put there: the annotation rule and the "Von dir" label are
    /// `oklch(.7 .11 250)`. Dropped to the same lightness the term highlight
    /// sits at, it reads as a background rather than as ink, and it says
    /// "yours" in the vocabulary the design already established — without a new
    /// hue and without competing with the model's own emphasis on the same
    /// line.
    static var highlightBackground: Color {
        RetainColor(OKLCH(0.38, 0.06, 250)).color
    }

    /// Matching the term highlight's own geometry, so two marks on one line sit
    /// on the same baseline rather than stacking two different shapes.
    static let highlightCornerRadius: CGFloat = 3
    static let highlightHorizontalPadding: CGFloat = 3
}
