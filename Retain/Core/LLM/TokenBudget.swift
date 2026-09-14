import Foundation

/// Guesses how many tokens a prompt will take.
///
/// Retain sends `contextOverflowPolicy: "stopAtLimit"` — hard rule 13 — which
/// means a prompt that does not fit does not get silently halved; the server
/// stops and says so. That is the right behaviour, but it is a report after the
/// fact. This type is the check before it, so a reduce that cannot possibly fit
/// is refused with a number the user can act on instead of burning two minutes
/// of a 30B model to arrive at a truncated answer.
///
/// **It is an estimate and is written to overestimate.** German is tokenised
/// badly by every Latin-script BPE vocabulary in use — compounds such as
/// *Seitenersetzungsalgorithmus* split into five or six pieces where the
/// English equivalent takes two — so the usual four-characters-per-token rule
/// of thumb understates German by a third and would let a prompt through that
/// then does not fit.
nonisolated enum TokenBudget {

    /// Characters per token, for German through a Llama-family vocabulary.
    static let charactersPerToken = 2.8

    /// Tokens added per message for the chat template's own role markers.
    static let perMessageOverhead = 8

    /// How much of the context is left for the answer.
    ///
    /// A prompt that fills the whole window leaves the model nowhere to write,
    /// and the stop reason for that is `contextLengthReached` after it has
    /// already produced half a note. A fifth is enough for a reduce over a
    /// ninety-minute recording and small enough not to reject prompts that would
    /// have worked.
    static let answerShare = 0.2

    static func estimatedTokens(in text: String) -> Int {
        Int((Double(text.count) / charactersPerToken).rounded(.up))
    }

    static func estimatedTokens(in conversation: ChatConversation) -> Int {
        conversation.messages.reduce(0) { total, message in
            total + estimatedTokens(in: message.content) + perMessageOverhead
        }
    }

    /// Whether `conversation` fits into a context of `contextLength` tokens with
    /// room left to answer.
    static func fits(_ conversation: ChatConversation, in contextLength: Int) -> Bool {
        estimatedTokens(in: conversation) <= promptAllowance(of: contextLength)
    }

    /// The share of a context window a prompt may use.
    static func promptAllowance(of contextLength: Int) -> Int {
        Int(Double(contextLength) * (1 - answerShare))
    }
}
