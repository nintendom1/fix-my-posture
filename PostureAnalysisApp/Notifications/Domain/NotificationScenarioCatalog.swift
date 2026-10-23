import Foundation

enum NotificationScenarioCatalogError: Error, LocalizedError, Equatable {
    case missingDataAsset
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missingDataAsset:
            "The notification scenario data is missing from the app."
        case .invalid(let reason):
            "The notification scenario data is invalid: \(reason)"
        }
    }
}

/// The notification scenarios the app ships with, loaded from the `NotificationScenarios` data set.
struct NotificationScenarioCatalog: Equatable {
    static let dataAssetName = "NotificationScenarios"

    let sampleSuggestion: String
    let scenarios: [NotificationScenario]

    private struct Document: Decodable {
        let version: Int
        let sampleSuggestion: String
        let scenarios: [NotificationScenario]
    }

    init(data: Data) throws {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw NotificationScenarioCatalogError.invalid(error.localizedDescription)
        }
        guard document.version == 1 else {
            throw NotificationScenarioCatalogError.invalid("unsupported version \(document.version)")
        }
        var seen = Set<String>()
        for scenario in document.scenarios {
            guard seen.insert(scenario.id).inserted else {
                throw NotificationScenarioCatalogError.invalid("duplicate scenario \(scenario.id)")
            }
            guard !scenario.art.isEmpty, !scenario.copy.isEmpty else {
                throw NotificationScenarioCatalogError.invalid("scenario \(scenario.id) has no art or copy")
            }
        }
        sampleSuggestion = document.sampleSuggestion
        scenarios = document.scenarios
    }

    func scenario(id: String) -> NotificationScenario? {
        scenarios.first { $0.id == id }
    }

    func scenarios(of kind: NotificationScenario.Kind) -> [NotificationScenario] {
        scenarios.filter { $0.kind == kind }
    }
}
