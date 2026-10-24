import Foundation

/// Fills `{token}` placeholders from string values. Same rules as `NotificationTemplate`, but persona tokens
/// are free-form names declared in persona-content.json rather than a fixed enum.
enum PersonaTemplate {
    /// The filled text, or nil when it names a token with no value or has unbalanced braces.
    static func render(_ template: String, values: [String: String]) -> String? {
        // Implemented by P4.
        nil
    }

    /// Token names used in `template`, in order of appearance.
    static func tokens(in template: String) -> [String] {
        // Implemented by P4.
        []
    }
}
