import UIKit

private final class PersonaContentBundleToken {}

extension PersonaContentCatalog {
    /// Loads the `PersonaContent` data set generated from Design/NotificationCharacter/persona-content.json.
    static func bundled(bundle: Bundle = Bundle(for: PersonaContentBundleToken.self)) throws -> PersonaContentCatalog {
        guard let asset = NSDataAsset(name: dataAssetName, bundle: bundle) else {
            throw PersonaContentCatalogError.missingDataAsset
        }
        return try PersonaContentCatalog(data: asset.data)
    }
}
