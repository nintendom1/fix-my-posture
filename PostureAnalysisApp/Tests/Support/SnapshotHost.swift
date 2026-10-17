import SwiftUI
import UIKit
import XCTest
import QuartzCore
@testable import PostureAnalysisApp

struct SnapshotResult {
    let image: UIImage
    let anchors: [String: CGRect]
    let window: UIWindow
}

enum SnapshotHost {
    @MainActor
    static func render<Content: View>(
        _ content: Content,
        frameId: String,
        testCase: XCTestCase? = nil
    ) throws -> SnapshotResult {
        UIView.setAnimationsEnabled(false)
        CATransaction.setDisableActions(true)
        DesignAnchorRegistry.shared.reset()

        let hostedContent = content
            .transaction { $0.disablesAnimations = true }
            .environment(\.dynamicTypeSize, .large)
            .environment(\.motionPolicy, .reduced)
            .preferredColorScheme(.dark)
        let controller = UIHostingController(rootView: hostedContent)
        let window = DesignWindow()
        let previousKeyWindow = UIApplication.shared.windows.first(where: \.isKeyWindow)
        window.rootViewController = controller
        controller.view.backgroundColor = .clear
        controller.view.frame = window.bounds
        window.makeKeyAndVisible()

        for _ in 0..<5 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: DesignWindow.fixedSize, format: format)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let result = SnapshotResult(image: image, anchors: DesignAnchorRegistry.shared.frames, window: window)

        if let directory = snapshotDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(frameId).png")
            if let data = image.pngData() { try data.write(to: url, options: .atomic) }
        }
        if let testCase {
            let attachment = XCTAttachment(image: image)
            attachment.name = "Design snapshot · \(frameId)"
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
        }

        window.isHidden = true
        previousKeyWindow?.makeKey()
        return result
    }

    private static var snapshotDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FMP_SNAPSHOT_DIR"] ?? environment["TEST_RUNNER_FMP_SNAPSHOT_DIR"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
