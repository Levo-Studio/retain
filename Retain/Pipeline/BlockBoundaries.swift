import Foundation

/// Decides where a recording is cut into blocks.
///
/// Pure, and the only thing in Retain that knows what "every three minutes"
/// means. Given the same lines and the same markers it gives the same blocks,
/// which is what lets the rule be argued about in a test rather than watched
/// for over the course of an actual class.
///
/// **Three minutes of speech, not of wall clock.** The two are nowhere near the
/// same thing in a real room. Ten minutes of an exercise, a projector that will
/// not connect, a class writing something down — measured against the clock,
/// each of those closes three blocks with nothing in them, and the notes fill
/// up with cards summarising silence. Measured against speech, the block simply
/// stays open until somebody says enough to summarise.
nonisolated enum BlockBoundaries {

    /// About three minutes of speech.
    ///
    /// Long enough that a card is a topic rather than a sentence, short enough
    /// that the first card appears while the user still remembers the opening.
    /// It is also roughly what a 3–8B model handles without losing the thread:
    /// three minutes is some five hundred words.
    static let speechBudget: TimeInterval = 180

    /// A marker cannot close a block holding less speech than this.
    ///
    /// `⌘⇧M` is pressed in bursts — the lecturer says "this is in the exam" and
    /// the room marks it twice in ten seconds. Without a floor, that produces
    /// two cards summarising one sentence each, and the third one summarising
    /// the rest of the topic with its opening cut off. A marker below the floor
    /// still lands in the block; it just does not end it.
    static let minimumSpeech: TimeInterval = 45

    /// Cuts `lines` into blocks.
    ///
    /// - Parameters:
    ///   - lines: transcript lines in order. While the recording runs these are
    ///     provisional ones — they are all there is — and afterwards the batch
    ///     pass replaces them and the blocks are cut again.
    ///   - markers: every `⌘⇧M`, in any order.
    ///   - finished: `false` while the recording is still running, which leaves
    ///     the trailing block `.open` instead of closing it. Closing it would
    ///     send half a topic to the model and put a card in the notes that the
    ///     next card then repeats.
    static func blocks(
        from lines: [TranscriptLine],
        markers: [RecordingMarker] = [],
        finished: Bool = true,
        speechBudget: TimeInterval = BlockBoundaries.speechBudget,
        minimumSpeech: TimeInterval = BlockBoundaries.minimumSpeech
    ) -> [TranscriptBlock] {
        guard !lines.isEmpty else { return [] }

        let ordered = markers.sorted { $0.time < $1.time }

        var blocks: [TranscriptBlock] = []
        var current: [TranscriptLine] = []
        var held: [RecordingMarker] = []
        var speech: TimeInterval = 0
        var next = 0

        func close(_ closing: TranscriptBlock.Closing) {
            guard !current.isEmpty else { return }
            blocks.append(
                TranscriptBlock(
                    number: blocks.count + 1,
                    lines: current,
                    markers: held,
                    closing: closing
                )
            )
            current = []
            held = []
            speech = 0
        }

        for line in lines {
            current.append(line)
            speech += max(0, line.duration)

            // A marker belongs to the block that was open when it was pressed.
            // Anything before the first line — the user marked something during
            // the silence before anyone spoke — lands in the first block, which
            // is the only place it can be read in context.
            while next < ordered.count, ordered[next].time <= line.end {
                held.append(ordered[next])
                next += 1
            }

            if speech >= speechBudget {
                // Budget before marker when both are true. The marker is still
                // recorded on the block; only the reason differs, and a block
                // that ran its full length closed because it ran its full
                // length.
                close(.speechBudget)
            } else if !held.isEmpty, speech >= minimumSpeech {
                close(.marker)
            }
        }

        // Markers after the last spoken line: the user marked something as the
        // recording ended.
        while next < ordered.count {
            held.append(ordered[next])
            next += 1
        }

        if !current.isEmpty {
            close(finished ? .endOfRecording : .open)
        } else if !held.isEmpty, var last = blocks.popLast() {
            last.markers.append(contentsOf: held)
            blocks.append(last)
        }

        return blocks
    }

    /// The blocks that are ready to summarise right now.
    ///
    /// The open one is left out on purpose: it is the card the design draws
    /// dim, and sending it would spend the small model on a topic that is still
    /// being spoken.
    static func closed(_ blocks: [TranscriptBlock]) -> [TranscriptBlock] {
        blocks.filter { !$0.isOpen }
    }
}
