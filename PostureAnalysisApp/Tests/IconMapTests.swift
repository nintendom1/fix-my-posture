import XCTest
import UIKit
@testable import PostureAnalysisApp

final class IconMapTests: XCTestCase {
    func testDragIndicatorUsesTheMaterialTwoByThreeDotGrip() {
        XCTAssertEqual(IconMap.symbol(for: "drag_indicator"), "circle.grid.2x2.fill")
    }

    func testEveryDesignMetricMaterialIconMapsToAnAvailableIOS17Symbol() throws {
        let names = try DesignMetrics.load().allIcons
        XCTAssertEqual(names.count, 60)

        for materialName in names {
            guard let symbol = IconMap.symbol(for: materialName) else {
                XCTFail("Missing SF Symbol mapping for Material Symbol \(materialName)")
                continue
            }
            XCTAssertNotNil(UIImage(systemName: symbol), "\(materialName) maps to unavailable SF Symbol \(symbol)")
        }
    }

    func testMaterialIconMappingsAreOneToOneUnlessExplicitlyAllowed() throws {
        let names = try DesignMetrics.load().allIcons
        let grouped = Dictionary(grouping: names.compactMap { name -> (String, String)? in
            IconMap.symbol(for: name).map { ($0, name) }
        }, by: { $0.0 })

        for (symbol, values) in grouped where values.count > 1 {
            let materialNames = Set(values.map { $0.1 })
            XCTAssertNotNil(IconMap.duplicateAllowlist[symbol], "Duplicate mapping for \(materialNames) → \(symbol) needs an explicit reason")
        }
    }
}
