import Foundation

/// Builders for the response schemas Retain sends to the model.
///
/// Thin on purpose. Only the handful of JSON Schema that a local server's
/// constrained decoder actually honours is here — types, descriptions, required
/// and item bounds. Anything richer (`oneOf`, `pattern`, `$ref`) is either
/// ignored or turns into a grammar the model cannot satisfy, and a schema the
/// server silently drops is worse than no schema, because the fallback ladder
/// never gets a chance to notice.
nonisolated enum JSONSchema {

    static func string(_ description: String) -> JSONValue {
        .object([
            ("type", .string("string")),
            ("description", .string(description)),
        ])
    }

    static func array(of element: JSONValue, _ description: String, maximum: Int? = nil) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("type", .string("array")),
            ("description", .string(description)),
            ("items", element),
        ]
        if let maximum {
            pairs.append(("maxItems", .integer(maximum)))
        }
        return .object(pairs)
    }

    /// An object schema.
    ///
    /// Every property is listed in `required` and `additionalProperties` is
    /// false, always. Strict mode on LM Studio rejects a schema whose required
    /// list is shorter than its properties, and a field the model is allowed to
    /// omit is a field it will omit. Where a value is genuinely optional —
    /// the emphasised term — the model is told in the description to send an
    /// empty string, which decodes and is then treated as absent. That is a
    /// contract a 3–8B model keeps; "omit this key" is not.
    static func object(_ description: String, _ properties: [(String, JSONValue)]) -> JSONValue {
        .object([
            ("type", .string("object")),
            ("description", .string(description)),
            ("properties", .object(properties.map { (key: $0.0, value: $0.1) })),
            ("required", .array(properties.map { .string($0.0) })),
            ("additionalProperties", .boolean(false)),
        ])
    }
}

/// A schema with the name the API wants alongside it.
nonisolated struct SchemaDescription: Sendable, Equatable {

    /// `json_schema.name`. Lowercase and underscored, because some servers
    /// reject anything else.
    let name: String

    let schema: JSONValue
}
