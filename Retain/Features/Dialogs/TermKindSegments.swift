import SwiftUI

/// Half-year or semester.
///
/// **Nothing in the export draws this.** It is the one control the written
/// brief asks for that the design does not have, so rather than invent a shape
/// it borrows one the export already uses: the segment pair on board 03, which
/// is `500 · 12px` centred in an 8-point rounded rectangle, 7 points of vertical
/// padding, 3 between the two, selected on the selected-row fill in primary ink
/// and unselected in label ink with no fill at all.
///
/// The choice is **per term**, not per app: somebody who changes school, or
/// changes country, keeps the half-years they already recorded as half-years
/// instead of having them silently re-labelled.
struct TermKindSegments: View {

    @Binding var kind: TermKind

    var body: some View {
        HStack(spacing: RetainMetrics.segmentGap) {
            ForEach(TermKind.allCases, id: \.self) { option in
                Button {
                    kind = option
                } label: {
                    Text(option.title)
                        .retainStyle(RetainTypography.segment)
                        .foregroundStyle(kind == option ? RetainPalette.inkPrimary : RetainPalette.inkLabel)
                        // The export's segments are `flex: 1` inside a 330-point
                        // rail, which is how they get their width. In a form
                        // the value column is 462 points wide and two segments
                        // filling it would read as two headings rather than as
                        // a pair, so each one takes the field's own horizontal
                        // padding instead and the pair hugs the left edge.
                        .padding(.vertical, RetainMetrics.segmentPadding.top)
                        .padding(.horizontal, RetainMetrics.fieldPadding.leading)
                        .background(
                            kind == option ? RetainPalette.surfaceSelectedRow : .clear,
                            in: RoundedRectangle(cornerRadius: RetainMetrics.radiusSegment)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}
