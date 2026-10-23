import SwiftUI
import XCTest
@testable import PostureAnalysisApp

/// Render smoke tests for the developer preview page. Set TEST_RUNNER_FMP_SNAPSHOT_DIR to also write PNGs.
@MainActor
final class NotificationPreviewScreenTests: XCTestCase {
    func testPageRendersTheSelectedNotificationAndScenarioList() throws {
        let viewModel = makeViewModel()

        let result = try SnapshotHost.render(screen(viewModel), frameId: "notification-preview-default", testCase: self)

        XCTAssertTrue(hasVisibleContent(result.image))
    }

    func testPageRendersACloseCropAcknowledgmentSelection() throws {
        let viewModel = makeViewModel()
        viewModel.select("established-streak-at-risk")
        viewModel.stepVariant(by: 1)

        let result = try SnapshotHost.render(screen(viewModel), frameId: "notification-preview-streak-at-risk", testCase: self)

        XCTAssertTrue(hasVisibleContent(result.image))
        XCTAssertEqual(viewModel.preview?.imageAssetName, "NotificationCharacter/sad-hoodie-close")
    }

    func testPageRendersTheErrorWhenScenarioDataIsMissing() throws {
        let viewModel = NotificationPreviewViewModel(
            catalog: nil,
            loadError: "The notification scenario data is missing from the app.",
            preferences: InMemoryPreferences(),
            scheduler: FakePreviewScheduler(),
            openSettings: {},
            sleep: { _ in }
        )

        let result = try SnapshotHost.render(screen(viewModel), frameId: "notification-preview-error", testCase: self)

        XCTAssertTrue(hasVisibleContent(result.image))
    }

    private func makeViewModel() -> NotificationPreviewViewModel {
        NotificationPreviewViewModel(
            catalog: try? NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self)),
            preferences: InMemoryPreferences(),
            scheduler: FakePreviewScheduler(),
            openSettings: {},
            sleep: { _ in }
        )
    }

    private func screen(_ viewModel: NotificationPreviewViewModel) -> some View {
        NavigationStack { NotificationPreviewScreen(viewModel: viewModel) }
            .environment(\.colorScheme, .dark)
    }

    /// A blank render is one flat color; a rendered page has many.
    private func hasVisibleContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data as Data? else { return false }
        var colors = Set<[UInt8]>()
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        for offset in stride(from: 0, to: data.count - bytesPerPixel, by: bytesPerPixel * 997) {
            colors.insert(Array(data[offset..<offset + bytesPerPixel]))
        }
        return colors.count > 20
    }
}
