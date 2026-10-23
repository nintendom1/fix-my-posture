import Foundation
import UIKit
import XCTest
@testable import PostureAnalysisApp

final class NotificationScenarioCatalogTests: XCTestCase {
    private let appBundle = Bundle(for: AppEnvironment.self)

    func testBundledCatalogLoadsEveryScenarioFromTheDataSet() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: appBundle)

        XCTAssertGreaterThanOrEqual(catalog.scenarios.count, 35)
        XCTAssertEqual(Set(catalog.scenarios.map(\.id)).count, catalog.scenarios.count)
        XCTAssertFalse(catalog.scenarios(of: .nudge).isEmpty)
        XCTAssertFalse(catalog.scenarios(of: .acknowledgment).isEmpty)
        XCTAssertEqual(catalog.scenario(id: "session-completed")?.kind, .acknowledgment)
        XCTAssertEqual(catalog.scenario(id: "established-streak-at-risk")?.art.first?.crop, .close)
        XCTAssertNil(catalog.scenario(id: "no-such-scenario"))
    }

    func testEveryArtEntryHasAnImageInTheAssetCatalog() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: appBundle)

        for scenario in catalog.scenarios {
            for art in scenario.art {
                let image = UIImage(named: art.assetName, in: appBundle, compatibleWith: nil)
                XCTAssertNotNil(image, "\(scenario.id) is missing \(art.assetName)")
                XCTAssertEqual(image?.size, CGSize(width: 512, height: 512), art.assetName)
            }
        }
    }

    func testEveryTitleAndCopyLineFillsFromItsSampleValues() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: appBundle)

        for scenario in catalog.scenarios {
            let values = scenario.sampleValues(suggestion: catalog.sampleSuggestion)
            XCTAssertNotNil(NotificationTemplate.render(scenario.title, values: values), "\(scenario.id) title")
            for line in scenario.copy {
                XCTAssertNotNil(NotificationTemplate.render(line, values: values), "\(scenario.id): \(line)")
            }
            XCTAssertGreaterThanOrEqual(scenario.copy.count, scenario.art.count, "\(scenario.id) alternates unreachable")
        }
    }

    func testEveryScenarioBuildsContentForEveryVariant() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: appBundle)

        for scenario in catalog.scenarios {
            let values = scenario.sampleValues(suggestion: catalog.sampleSuggestion)
            for variant in 0..<scenario.copy.count {
                let content = NotificationContentBuilder.make(scenario: scenario, variant: variant, values: values)
                XCTAssertNotNil(content, "\(scenario.id) variant \(variant)")
                XCTAssertFalse(content?.body.isEmpty ?? true)
                XCTAssertFalse(content?.body.contains("{") ?? true, "\(scenario.id) left a placeholder")
            }
        }
    }

    func testInvalidDataIsRejectedWithAReason() {
        XCTAssertThrowsError(try NotificationScenarioCatalog(data: Data("not json".utf8))) { error in
            guard case NotificationScenarioCatalogError.invalid = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try NotificationScenarioCatalog(data: json(version: 2, scenarios: [scenarioJSON(id: "a")])))
        XCTAssertThrowsError(try NotificationScenarioCatalog(
            data: json(scenarios: [scenarioJSON(id: "a"), scenarioJSON(id: "a")])
        ))
        XCTAssertThrowsError(try NotificationScenarioCatalog(data: json(scenarios: [scenarioJSON(id: "a", copy: "")])))
        XCTAssertThrowsError(try NotificationScenarioCatalog(data: json(scenarios: [scenarioJSON(id: "a", art: "")])))
    }

    func testAValidMinimalCatalogDecodes() throws {
        let catalog = try NotificationScenarioCatalog(data: json(scenarios: [scenarioJSON(id: "a"), scenarioJSON(id: "b")]))

        XCTAssertEqual(catalog.scenarios.map(\.id), ["a", "b"])
        XCTAssertEqual(catalog.sampleSuggestion, "Sample")
        XCTAssertEqual(catalog.scenarios[0].art[0].assetName, "NotificationCharacter/smile-hoodie-portrait")
        XCTAssertEqual(catalog.scenarios[0].art[0].label, "smile · hoodie · portrait")
    }

    private func json(version: Int = 1, scenarios: [String]) -> Data {
        Data("""
        {"version": \(version), "sampleSuggestion": "Sample", "scenarios": [\(scenarios.joined(separator: ","))]}
        """.utf8)
    }

    private func scenarioJSON(
        id: String,
        art: String = #"{"expression":"smile","outfit":"hoodie","crop":"portrait"}"#,
        copy: String = #""Hello""#
    ) -> String {
        """
        {"id":"\(id)","name":"Name","kind":"nudge","trigger":"t","tone":"t","art":[\(art)],
         "title":"Title","copy":[\(copy)],"sample":{}}
        """
    }
}
