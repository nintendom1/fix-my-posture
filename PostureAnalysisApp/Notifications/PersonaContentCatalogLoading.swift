import UIKit

extension PersonaContentCatalog {
    /// Loads the `PersonaContent` data set generated from Design/NotificationCharacter/persona-content.json.
    static func bundled(bundle: Bundle = .main) throws -> PersonaContentCatalog {
        // Implemented by P4 (mirror NotificationScenarioCatalog.bundled).
        throw PersonaContentCatalogError.missingDataAsset
    }
}
