import Foundation

/// A JSON value Retain builds by hand.
///
/// It exists for one thing: the request Retain sends to LM Studio, and above
/// all the response schema inside it. **The order of the properties in a schema
/// is not decoration.** A local server turns the schema into a grammar and
/// constrains the model to emit the fields in the order the schema lists them,
/// and the first field a model writes shapes everything it writes after.
///
/// Which rules out both obvious ways of building the JSON:
///
/// - a Swift `Dictionary` has no order at all;
/// - `JSONEncoder`'s keyed container **does not preserve the order its keys
///   were encoded in.** It comes out of a hash table, differently on every
///   launch of the same binary. That is not a theory — it is what the test
///   below this type caught, and it is why the serialiser here is written by
///   hand rather than delegated.
nonisolated indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case null
    case array([JSONValue])

    /// Ordered. See the type comment.
    case object([(key: String, value: JSONValue)])

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): a == b
        case (.integer(let a), .integer(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.boolean(let a), .boolean(let b)): a == b
        case (.null, .null): true
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }
}

// MARK: - Serialising

extension JSONValue {

    /// The value as compact JSON, with object keys in the order they were
    /// written.
    nonisolated var serialized: String {
        switch self {
        case .string(let value):
            Self.quoted(value)
        case .integer(let value):
            String(value)
        case .number(let value):
            String(value)
        case .boolean(let value):
            value ? "true" : "false"
        case .null:
            "null"
        case .array(let values):
            "[" + values.map(\.serialized).joined(separator: ",") + "]"
        case .object(let pairs):
            "{" + pairs.map { Self.quoted($0.key) + ":" + $0.value.serialized }.joined(separator: ",") + "}"
        }
    }

    nonisolated var data: Data {
        Data(serialized.utf8)
    }

    /// A JSON string literal.
    ///
    /// Only the escapes JSON requires: the quote, the backslash and the control
    /// characters. Everything above `U+001F` is written as itself, because the
    /// body is sent as UTF-8 and escaping German to `ä` would triple the
    /// size of a transcript for no benefit.
    private nonisolated static func quoted(_ text: String) -> String {
        var out = "\""
        out.unicodeScalars.reserveCapacity(text.unicodeScalars.count + 2)

        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }

        return out + "\""
    }
}
