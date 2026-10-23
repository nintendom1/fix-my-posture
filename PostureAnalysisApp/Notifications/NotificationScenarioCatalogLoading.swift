import UIKit

private final class NotificationBundleToken {}

extension NotificationScenarioCatalog {
    /// Loads the `NotificationScenarios` data set compiled into the app.
    static func bundled(bundle: Bundle = Bundle(for: NotificationBundleToken.self)) throws -> NotificationScenarioCatalog {
        guard let asset = NSDataAsset(name: dataAssetName, bundle: bundle) else {
            throw NotificationScenarioCatalogError.missingDataAsset
        }
        return try NotificationScenarioCatalog(data: asset.data)
    }
}
