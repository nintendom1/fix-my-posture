import Foundation

/// Fills `{token}` placeholders from string values. Same rules as `NotificationTemplate`, but persona tokens
/// are free-form names declared in persona-content.json rather than a fixed enum.
enum PersonaTemplate {
    /// The filled text, or nil when it names a token with no value (an empty string counts as no value) or has
    /// unbalanced braces.
    static func render(_ template: String, values: [String: String]) -> String? {
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            if let strayClose = rest.firstIndex(of: "}"), strayClose < open { return nil }
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let name = String(rest[rest.index(after: open)..<close])
            guard let value = values[name], !value.isEmpty else { return nil }
            result += value
            rest = rest[rest.index(after: close)...]
        }
        guard !rest.contains("}") else { return nil }
        result += rest
        return result
    }

    /// Token names used in `template`, in order of appearance.
    static func tokens(in template: String) -> [String] {
        var names: [String] = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { break }
            names.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }
}
