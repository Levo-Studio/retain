import Foundation

/// Turns anonymous diarization clusters into the two roles the design draws.
///
/// Diarization says "these stretches are the same voice" and nothing more — the
/// clusters come out as `Speaker_1`, `Speaker_2` and so on, in no meaningful
/// order. Deciding which of them is the person teaching is a judgement about
/// lectures, not about audio, so it lives here as a pure function over
/// durations and is tested against the shapes a real lecture takes.
///
/// The rule: **the cluster that speaks the longest is the lecturer, and
/// everyone else is the audience.** In a lecture that is not close — the person
/// teaching usually holds eighty per cent or more of the hour, and a question
/// from the room is fifteen seconds.
nonisolated enum SpeakerRoles {

    /// Below this share of total speech, the leading cluster is not treated as
    /// a lecturer at all and every line comes back `.unknown`.
    ///
    /// The case this guards is a recording that is not a lecture: a seminar
    /// where four people talk in turn, or a room where the microphone caught
    /// the neighbours better than the front. Guessing a lecturer out of four
    /// even shares would put a confident wrong label on the whole transcript,
    /// and a wrong label is worse than no label — it is the thing the reader
    /// stops checking.
    static let dominanceThreshold: Double = 0.5

    /// Maps each cluster to a role.
    ///
    /// - Returns: a role for every cluster in `segments`. Empty input gives an
    ///   empty map rather than a guess.
    static func assign(_ segments: [SpeakerSegment]) -> [String: SpeakerRole] {
        guard !segments.isEmpty else { return [:] }

        var spoken: [String: TimeInterval] = [:]
        for segment in segments where segment.duration > 0 {
            spoken[segment.speakerID, default: 0] += segment.duration
        }
        guard !spoken.isEmpty else { return [:] }

        let total = spoken.values.reduce(0, +)
        guard total > 0 else { return [:] }

        // Sort by duration, then by id, so the answer does not depend on the
        // order a dictionary happened to hash into. Two clusters with exactly
        // equal time is contrived, but a result that changes between runs is
        // the kind of bug nobody can reproduce.
        let ranked = spoken.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }

        guard let leader = ranked.first, leader.value / total >= dominanceThreshold else {
            return spoken.keys.reduce(into: [:]) { $0[$1] = .unknown }
        }

        return spoken.keys.reduce(into: [:]) { result, id in
            result[id] = (id == leader.key) ? .lecturer : .audience
        }
    }

    /// Applies `assign` to the segments and hands back a lookup that answers
    /// "who was speaking at this second".
    ///
    /// Where nothing was segmented — a gap, or a stretch diarization gave up on
    /// — the answer is `.unknown` rather than the nearest neighbour. Extending
    /// a speaker across a gap is how a single stray line ends up attributed to
    /// the wrong person for a minute.
    static func role(at time: TimeInterval, in segments: [SpeakerSegment], roles: [String: SpeakerRole]) -> SpeakerRole {
        for segment in segments where time >= segment.start && time < segment.end {
            return roles[segment.speakerID] ?? .unknown
        }
        return .unknown
    }
}
