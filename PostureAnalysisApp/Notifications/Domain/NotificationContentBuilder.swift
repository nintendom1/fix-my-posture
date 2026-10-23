import Foundation

/// Fills `{token}` placeholders in a title or copy line.
enum NotificationTemplate {
    /// The filled text, or nil when it names an unknown token or one with no value.
    static func render(_ template: String, values: NotificationValues) -> String? {
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let name = String(rest[rest.index(after: open)..<close])
            guard let token = NotificationToken(rawValue: name), let value = values[token] else { return nil }
            result += value
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

/// The notification categories the app sets on character notifications.
enum NotificationCategory {
    static let nudge = "fixMyPosture.character.nudge"
    static let acknowledgment = "fixMyPosture.character.acknowledgment"

    static func identifier(for kind: NotificationScenario.Kind) -> String {
        switch kind {
        case .nudge: nudge
        case .acknowledgment: acknowledgment
        }
    }

    /// iOS hides banners for local notifications while the app is open unless the app opts in. Only
    /// acknowledgments opt in, so they pop up over the workout summary; nudges appear only after the user leaves.
    static func showsInForeground(_ categoryIdentifier: String) -> Bool {
        categoryIdentifier == acknowledgment
    }
}

/// A character notification ready to be handed to the system.
struct CharacterNotificationContent: Equatable {
    let scenarioID: String
    let kind: NotificationScenario.Kind
    let title: String
    let body: String
    let imageAssetName: String
    let artLabel: String

    var categoryIdentifier: String { NotificationCategory.identifier(for: kind) }
}

enum NotificationContentBuilder {
    /// Shown when a title's token has no value, such as a missing suggestion.
    static let fallbackTitle = "Fix My Posture"

    /// Picks the art and copy for a variant and fills their tokens. The variant wraps around, so any integer works.
    /// Copy lines that cannot be filled are skipped; the result is nil only when none of them can.
    static func make(
        scenario: NotificationScenario,
        variant: Int,
        values: NotificationValues
    ) -> CharacterNotificationContent? {
        let art = scenario.art[wrapped(variant, count: scenario.art.count)]
        let copyStart = wrapped(variant, count: scenario.copy.count)
        for offset in 0..<scenario.copy.count {
            let line = scenario.copy[(copyStart + offset) % scenario.copy.count]
            guard let body = NotificationTemplate.render(line, values: values) else { continue }
            return CharacterNotificationContent(
                scenarioID: scenario.id,
                kind: scenario.kind,
                title: NotificationTemplate.render(scenario.title, values: values) ?? fallbackTitle,
                body: body,
                imageAssetName: art.assetName,
                artLabel: art.label
            )
        }
        return nil
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
