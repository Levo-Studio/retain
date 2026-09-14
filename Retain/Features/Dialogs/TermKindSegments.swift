import SwiftUI

/// Half-year or semester.
///
/// **Nothing in the export draws this.** It is the one control the written
/// brief asks for that the design does not have, so rather than invent a shape
/// it borrows one the export already uses: the segment pair on board 03, which
/// `RetainSegment` is.
///
/// The choice is **per term**, not per app: somebody who changes school, or
/// changes country, keeps the half-years they already recorded as half-years
/// instead of having them silently re-labelled.
struct TermKindSegments: View {

    @Binding var kind: TermKind

    var body: some View {
        HStack(spacing: RetainMetrics.segmentGap) {
            ForEach(TermKind.allCases, id: \.self) { option in
                RetainSegment(
                    title: option.title,
                    isSelected: kind == option,
                    select: { kind = option }
                )
            }
            Spacer(minLength: 0)
        }
    }
}
