import SwiftUI
import UIKit
import XCTest
import QuartzCore
@testable import PostureAnalysisApp

struct SnapshotResult {
    let image: UIImage
    let anchors: [String: CGRect]
    let snapshotMeasuredAnchors: [String: CGRect]
    let window: UIWindow
    let hostSafeAreaInsets: UIEdgeInsets
    let hostFrameInWindow: CGRect

    var magentaMarkerFrame: CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if bytes[offset] > 200, bytes[offset + 1] < 60,
                   bytes[offset + 2] > 200, bytes[offset + 3] > 200 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let scale = image.scale
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }
}

enum SnapshotHost {
    @MainActor
    static func render<Content: View>(
        _ content: Content,
        frameId: String,
        testCase: XCTestCase? = nil,
        markerAnchor: String? = nil
    ) throws -> SnapshotResult {
        UIView.setAnimationsEnabled(false)
        CATransaction.setDisableActions(true)
        DesignAnchorRegistry.shared.reset()

        let hostedContent = content
            .transaction { $0.disablesAnimations = true }
            .environment(\.dynamicTypeSize, .large)
            .environment(\.motionPolicy, .reduced)
            .environment(\.designAnchorMarkerName, markerAnchor)
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

        let anchorsAtCapture = DesignAnchorRegistry.shared.frames
        let hostSafeAreaInsets = controller.view.safeAreaInsets
        let hostFrameInWindow = controller.view.convert(controller.view.bounds, to: window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: DesignWindow.fixedSize, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        for _ in 0..<2 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
        let result = SnapshotResult(
            image: image,
            anchors: anchorsAtCapture,
            snapshotMeasuredAnchors: DesignAnchorRegistry.shared.frames,
            window: window,
            hostSafeAreaInsets: hostSafeAreaInsets,
            hostFrameInWindow: hostFrameInWindow
        )

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
