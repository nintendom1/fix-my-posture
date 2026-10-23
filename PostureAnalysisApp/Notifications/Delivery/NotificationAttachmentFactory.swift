import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Turns a notification image from the asset catalog into the file attachment iOS needs.
enum NotificationAttachmentFactory {
    /// The system moves an attachment's file into its own store, so each attachment gets its own temporary copy.
    static func makeAttachment(
        assetName: String,
        bundle: Bundle = .main,
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationCharacter", isDirectory: true)
    ) -> UNNotificationAttachment? {
        guard let png = UIImage(named: assetName, in: bundle, compatibleWith: nil)?.pngData() else { return nil }
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url)
            return try UNNotificationAttachment(
                identifier: "character",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
