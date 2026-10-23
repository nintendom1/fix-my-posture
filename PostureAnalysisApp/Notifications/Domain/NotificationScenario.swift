import Foundation

/// One state the notification character can be in, decoded from `notification-scenarios.json`.
/// That file is the single source of truth for the character's notification art and copy.
struct NotificationScenario: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        /// Scheduled ahead of time as a reminder.
        case nudge
        /// Sent about a second after a workout is saved.
        case acknowledgment
    }

    enum Crop: String, Codable {
        /// Head and shoulders.
        case portrait
        /// The tighter face crop used for heavier moments.
        case close
    }

    struct Art: Codable, Equatable, Hashable {
        let expression: String
        let outfit: String
        let crop: Crop

        /// The image's name in the namespaced `NotificationCharacter` asset folder.
        var assetName: String { "NotificationCharacter/\(expression)-\(outfit)-\(crop.rawValue)" }

        /// A short label such as "smile · hoodie · portrait".
        var label: String { "\(expression) · \(outfit) · \(crop.rawValue)" }
    }

    let id: String
    let name: String
    let kind: Kind
    /// What has to be true for this state, in the issue's words. Documentation only.
    let trigger: String
    let tone: String
    /// The first entry is the primary image; the rest are alternates picked by variant.
    let art: [Art]
    /// A short title that may use `{token}` placeholders.
    let title: String
    /// Interchangeable body lines that may use `{token}` placeholders.
    let copy: [String]
    /// Integer token values the developer preview uses for this state.
    let sample: [String: Int]
}

/// The placeholders a title or copy line may use.
enum NotificationToken: String, CaseIterable {
    case suggestion
    case streak
    case record
    case remaining
    case days
}

typealias NotificationValues = [NotificationToken: String]

extension NotificationScenario {
    /// Token values for the developer preview: this scenario's sample numbers plus a sample suggestion.
    func sampleValues(suggestion: String) -> NotificationValues {
        var values: NotificationValues = [.suggestion: suggestion]
        for (name, number) in sample {
            if let token = NotificationToken(rawValue: name) {
                values[token] = String(number)
            }
        }
        return values
    }
}
