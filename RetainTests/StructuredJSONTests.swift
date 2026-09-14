import Foundation
import Testing

@testable import Retain

private struct Answer: Codable, Equatable {
    let heading: String
    let summary: String
}

@Suite("Tolerant JSON extraction")
struct StructuredJSONTests {

    private let expected = Answer(heading: "Der TLB", summary: "Hält die letzten Übersetzungen.")
    private let object = """
        {"heading": "Der TLB", "summary": "Hält die letzten Übersetzungen."}
        """

    @Test("A clean answer decodes")
    func plainObject() throws {
        #expect(try StructuredJSON.decode(Answer.self, from: object) == expected)
    }

    @Test("A fenced answer decodes")
    func fencedObject() throws {
        let reply = """
            ```json
            \(object)
            ```
            """
        #expect(try StructuredJSON.decode(Answer.self, from: reply) == expected)
    }

    @Test("A fence with no language tag decodes")
    func untaggedFence() throws {
        #expect(try StructuredJSON.decode(Answer.self, from: "```\n\(object)\n```") == expected)
    }

    @Test("An answer with a sentence in front of it decodes")
    func proseBeforeTheObject() throws {
        let reply = "Klar, hier ist die Zusammenfassung:\n\n\(object)\n\nPasst das so?"
        #expect(try StructuredJSON.decode(Answer.self, from: reply) == expected)
    }

    /// A reasoning model drafts the JSON inside its `<think>` block, so the
    /// first braces in the reply are usually the wrong ones.
    @Test("A reasoning block in front of the answer is skipped")
    func reasoningBlockIsSkipped() throws {
        let reply = """
            <think>
            Ich sollte {"heading": "falsch"} zurückgeben. Nein, besser anders.
            </think>
            \(object)
            """
        #expect(try StructuredJSON.decode(Answer.self, from: reply) == expected)
    }

    /// Valid JSON that is not an answer. Taking the first thing that parses
    /// would stop here and never reach the object below it.
    @Test("An object of the wrong shape is passed over, not accepted")
    func wrongShapeIsSkipped() throws {
        let reply = """
            {"status": "ok"}
            \(object)
            """
        #expect(try StructuredJSON.decode(Answer.self, from: reply) == expected)
    }

    /// German note text contains braces about as often as anything else does.
    @Test("A brace inside a string does not end the object")
    func bracesInsideStringsAreIgnored() throws {
        // Wrapped in prose so the object has to be found rather than simply
        // being the whole reply.
        let reply = """
            Hier die Antwort:
            {"heading": "Mengen {a, b}", "summary": "Die Notation {} meint die leere Menge."}
            """
        let decoded = try StructuredJSON.decode(Answer.self, from: reply)
        #expect(decoded.heading == "Mengen {a, b}")
    }

    @Test("An escaped quote does not end the string")
    func escapedQuotesAreIgnored() throws {
        let reply = #"{"heading": "Der \"TLB\"", "summary": "Kurz."}"#
        #expect(try StructuredJSON.decode(Answer.self, from: reply).heading == "Der \"TLB\"")
    }

    @Test("An array at the top level is found too")
    func topLevelArrays() {
        #expect(StructuredJSON.candidates(in: "Hier: [1, 2, 3]").contains("[1, 2, 3]"))
    }

    @Test("Prose with no JSON in it is not an answer")
    func proseIsNotAnAnswer() {
        #expect(throws: (any Error).self) {
            try StructuredJSON.decode(Answer.self, from: "Es tut mir leid, dazu kann ich nichts sagen.")
        }
    }

    /// Repairing would be guessing, and a guessed note is worse than a missing
    /// one because nothing downstream can tell the two apart. What counts as
    /// broken is `JSONDecoder`'s judgement, not a second parser's — a trailing
    /// comma, for one, it accepts, and matching that here would mean writing a
    /// parser to disagree with the one actually used.
    @Test("Broken JSON is refused rather than repaired")
    func brokenJSONIsNotRepaired() {
        #expect(throws: (any Error).self) {
            try StructuredJSON.decode(Answer.self, from: #"{"heading": "Der TLB", "summary": "abgeschnitten"#)
        }
        #expect(throws: (any Error).self) {
            try StructuredJSON.decode(Answer.self, from: #"{heading: Der TLB, summary: abgeschnitten}"#)
        }
    }

    @Test("Each candidate is offered once")
    func candidatesAreUnique() {
        let candidates = StructuredJSON.candidates(in: object)
        #expect(candidates.count == Set(candidates).count)
    }
}

// MARK: -

@Suite("Ordered JSON")
struct JSONValueTests {

    /// The order of the properties in a schema is the order a constrained
    /// decoder makes the model write them in. Neither a dictionary nor
    /// `JSONEncoder` keeps it — which is why `JSONValue` serialises itself.
    @Test("Object keys come out in the order they went in")
    func orderIsPreserved() {
        let value = JSONValue.object([
            ("zuletzt", .string("a")),
            ("mitte", .integer(2)),
            ("anfang", .boolean(true)),
        ])

        for _ in 0..<50 {
            #expect(value.serialized == #"{"zuletzt":"a","mitte":2,"anfang":true}"#)
        }
    }

    @Test("The serialised value is valid JSON with every kind in it")
    func everyKindEncodes() throws {
        let value = JSONValue.object([
            ("text", .string("ä")),
            ("ganz", .integer(-3)),
            ("komma", .number(1.5)),
            ("wahr", .boolean(false)),
            ("nichts", .null),
            ("liste", .array([.integer(1), .string("zwei")])),
        ])

        let parsed = try #require(try JSONSerialization.jsonObject(with: value.data) as? [String: Any])

        #expect(parsed["text"] as? String == "ä")
        #expect(parsed["ganz"] as? Int == -3)
        #expect(parsed["komma"] as? Double == 1.5)
        #expect(parsed["wahr"] as? Bool == false)
        #expect(parsed["nichts"] is NSNull)
        #expect((parsed["liste"] as? [Any])?.count == 2)
    }

    @Test("Two objects are equal only when their order matches too")
    func equalityRespectsOrder() {
        let first = JSONValue.object([("a", .integer(1)), ("b", .integer(2))])
        let second = JSONValue.object([("b", .integer(2)), ("a", .integer(1))])

        #expect(first == first)
        #expect(first != second)
    }

    /// The prompt carries a German transcript, so the escaping has to be right
    /// and has to leave the German alone.
    @Test("Strings are escaped exactly as JSON needs and no further")
    func stringsAreEscaped() throws {
        let value = JSONValue.object([("t", .string("Er sagte \"ja\"\nund ging.\tSeitengröße\\Pfad"))])

        let parsed = try #require(try JSONSerialization.jsonObject(with: value.data) as? [String: Any])
        #expect(parsed["t"] as? String == "Er sagte \"ja\"\nund ging.\tSeitengröße\\Pfad")

        // Umlauts travel as themselves, not as six characters each.
        #expect(value.serialized.contains("Seitengröße"))
    }

    @Test("A control character becomes an escape rather than broken JSON")
    func controlCharactersAreEscaped() throws {
        let value = JSONValue.object([("t", .string("a\u{01}b"))])

        #expect(value.serialized.contains("\\u0001"))
        let parsed = try #require(try JSONSerialization.jsonObject(with: value.data) as? [String: Any])
        #expect(parsed["t"] as? String == "a\u{01}b")
    }
}

// MARK: -

@Suite("Token budget")
struct TokenBudgetTests {

    @Test("The estimate leaves room for the answer")
    func promptAllowanceLeavesRoom() {
        #expect(TokenBudget.promptAllowance(of: 4096) < 4096)
        #expect(TokenBudget.promptAllowance(of: 4096) == 3276)
    }

    /// The rule of thumb for English is four characters to a token. German
    /// compounds split into more pieces, so an English-sized estimate lets
    /// prompts through that then do not fit.
    @Test("German is estimated at more tokens than the English rule of thumb")
    func germanIsEstimatedGenerously() {
        let text = String(repeating: "Seitenersetzungsalgorithmus ", count: 100)
        let english = text.count / 4

        #expect(TokenBudget.estimatedTokens(in: text) > english)
    }

    @Test("A short prompt fits a small context and a lesson does not")
    func fitsAnswersBothWays() {
        let short = ChatConversation([.system("Fasse zusammen."), .user("Der TLB hält Übersetzungen.")])
        let lesson = ChatConversation([.user(String(repeating: "Wort ", count: 20_000))])

        #expect(TokenBudget.fits(short, in: 4096))
        #expect(!TokenBudget.fits(lesson, in: 4096))
        #expect(TokenBudget.fits(lesson, in: 128_000))
    }

    @Test("Each message costs something beyond its text")
    func messageOverheadIsCounted() {
        let one = ChatConversation([.user("abc")])
        let two = ChatConversation([.user("a"), .user("bc")])

        #expect(TokenBudget.estimatedTokens(in: two) > TokenBudget.estimatedTokens(in: one))
    }

    @Test("An empty prompt costs nothing")
    func emptyPromptIsFree() {
        #expect(TokenBudget.estimatedTokens(in: ChatConversation([])) == 0)
    }
}
