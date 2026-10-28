import SwiftUI
import UIKit
import XCTest
@testable import PostureAnalysisApp

final class ExerciseCatalogTests: XCTestCase {
    func testEveryExerciseHasOneBundledSquarePhotograph() throws {
        let photographs = ExercisePhotography.all
        let catalogIDs = Set(ExerciseCatalog.all.map(\.id))
        let photographIDs = Set(photographs.map(\.id))
        let placeholderIDs = Set(ExercisePhotography.placeholders.keys)
        XCTAssertTrue(photographIDs.isSubset(of: catalogIDs), "Photographs must belong to catalog exercises")
        XCTAssertTrue(placeholderIDs.isSubset(of: catalogIDs), "Placeholders must belong to catalog exercises")
        XCTAssertTrue(photographIDs.isDisjoint(with: placeholderIDs), "An exercise cannot use both a photo and a placeholder")
        XCTAssertEqual(Set(photographs.map(\.id)).count, photographs.count)
        XCTAssertEqual(Set(photographs.map(\.assetName)).count, photographs.count)

        for exercise in ExerciseCatalog.all {
            let photograph = ExercisePhotography.photograph(for: exercise.id)
            let placeholder = ExercisePhotography.placeholders[exercise.id]
            XCTAssertTrue(photograph != nil || placeholder != nil,
                          "\(exercise.id.rawValue) needs a photograph or a placeholder")
            XCTAssertFalse(photograph != nil && placeholder != nil,
                           "\(exercise.id.rawValue) cannot use both a photograph and a placeholder")

            if let photograph {
                let image = try XCTUnwrap(UIImage(named: photograph.assetName), "Missing asset for \(exercise.id.rawValue)")
                let pixels = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(pixels.width, 512)
                XCTAssertEqual(pixels.height, 512)
                XCTAssertEqual(photograph.sourceURL.scheme, "https")
            }
            if let placeholder {
                XCTAssertFalse(placeholder.isEmpty, "Missing placeholder symbol for \(exercise.id.rawValue)")
                XCTAssertNotNil(UIImage(systemName: placeholder), "Unknown SF Symbol \(placeholder)")
            }
        }

        XCTAssertNil(ExercisePhotography.photograph(for: ExerciseID(rawValue: "unavailable")))
    }

    @MainActor
    func testPlaceholderExerciseThumbnailRendersWithoutItsPhoto() throws {
        let view = ExerciseThumbnailView(exerciseID: .airSquat, placeholderSymbolName: "figure.stand")
        XCTAssertEqual(view.resolvedPlaceholderSymbolName, "figure.stand")
        XCTAssertNil(view.resolvedPhotograph, "A placeholder takes precedence over a bundled photo.")

        // An id with no photo, so without the placeholder branch only the plain one-color fallback would draw.
        let unknown = ExerciseID(rawValue: "placeholder-render-test")
        let placeholder = try XCTUnwrap(renderedColors(ExerciseThumbnailView(exerciseID: unknown, cornerRadius: 0,
                                                                             placeholderSymbolName: "figure.stand")))
        let fallback = try XCTUnwrap(renderedColors(ExerciseThumbnailView(exerciseID: unknown, cornerRadius: 0)))
        XCTAssertGreaterThan(placeholder.count, 20, "The placeholder draws a gradient and a symbol.")
        XCTAssertLessThanOrEqual(fallback.count, 2)
    }

    /// The distinct RGBA values a thumbnail renders at 112 × 88 points, scale 1.
    @MainActor
    private func renderedColors(_ view: ExerciseThumbnailView) -> Set<UInt32>? {
        let renderer = ImageRenderer(content: view.frame(width: 112, height: 88))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        var pixels = [UInt32](repeating: 0, count: image.width * image.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? Set(pixels) : nil
    }

    func testEveryCatalogExerciseHasCorePresentationData() {
        XCTAssertFalse(ExerciseCatalog.all.isEmpty)

        for exercise in ExerciseCatalog.all {
            let presentation = exercise.presentation
            XCTAssertFalse(presentation.shortName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Missing short name for \(exercise.id.rawValue)")
            XCTAssertFalse(presentation.muscles.isEmpty, "Missing muscles for \(exercise.id.rawValue)")
            XCTAssertTrue(presentation.muscles.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                          "Empty muscle label for \(exercise.id.rawValue)")
            XCTAssertFalse(presentation.filterGroups.isEmpty, "Missing filter groups for \(exercise.id.rawValue)")
        }
    }

    func testGluteBridgeIsRegisteredAfterRearLungeWithItsOwnPresentation() throws {
        let rearLungeIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .rearLunge })
        let bridgeIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .gluteBridge })
        XCTAssertEqual(bridgeIndex, rearLungeIndex + 1)
        let bridge = try XCTUnwrap(ExerciseCatalog.definition(for: .gluteBridge))
        XCTAssertEqual(bridge.presentation.gradient.token, .bridge)
        XCTAssertEqual(bridge.presentation.cameraSetupLine, "Floor-level side camera")
        XCTAssertEqual(bridge.presentation.filterGroups, [.lower, .bodyweight])
    }

    func testSitToStandIsRegisteredAfterAirSquatWithAPlaceholder() throws {
        let airSquatIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .airSquat })
        let sitToStandIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .sitToStand })
        XCTAssertEqual(sitToStandIndex, airSquatIndex + 1)
        let sitToStand = try XCTUnwrap(ExerciseCatalog.definition(for: .sitToStand))
        XCTAssertEqual(sitToStand.presentation.filterGroups, [.lower, .bodyweight])
        XCTAssertEqual(sitToStand.presentation.gradient.token, .sitToStand)
        XCTAssertEqual(sitToStand.presentation.symbolName, "figure.seated.side")
        XCTAssertEqual(ExercisePhotography.placeholders[.sitToStand], "figure.seated.side")
        XCTAssertNil(ExercisePhotography.photograph(for: .sitToStand))
    }

    func testWallPushUpIsRegisteredAfterPushUpWithAPlaceholder() throws {
        let pushUpIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .pushUp })
        let wallPushUpIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .wallPushUp })
        XCTAssertEqual(wallPushUpIndex, pushUpIndex + 1)
        let wallPushUp = try XCTUnwrap(ExerciseCatalog.definition(for: .wallPushUp))
        XCTAssertEqual(wallPushUp.presentation.filterGroups, [.upper, .bodyweight])
        XCTAssertEqual(wallPushUp.presentation.symbolName, "figure.strengthtraining.functional")
        XCTAssertEqual(ExercisePhotography.placeholders[.wallPushUp], "figure.strengthtraining.functional")
        XCTAssertNil(ExercisePhotography.photograph(for: .wallPushUp))
    }

    func testInclinePushUpIsRegisteredAfterWallPushUpWithAPlaceholder() throws {
        let wallPushUpIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .wallPushUp })
        let inclinePushUpIndex = try XCTUnwrap(ExerciseCatalog.all.firstIndex { $0.id == .inclinePushUp })
        XCTAssertEqual(inclinePushUpIndex, wallPushUpIndex + 1)
        let inclinePushUp = try XCTUnwrap(ExerciseCatalog.definition(for: .inclinePushUp))
        XCTAssertEqual(inclinePushUp.presentation.filterGroups, [.upper, .bodyweight])
        XCTAssertEqual(inclinePushUp.presentation.gradient.token, .inclinePushup)
        XCTAssertEqual(inclinePushUp.presentation.symbolName, "figure.strengthtraining.functional")
        XCTAssertEqual(ExercisePhotography.placeholders[.inclinePushUp], "figure.strengthtraining.functional")
        XCTAssertNil(ExercisePhotography.photograph(for: .inclinePushUp))
    }

    func testEveryPresentationSymbolResolves() {
        for exercise in ExerciseCatalog.all {
            XCTAssertNotNil(UIImage(systemName: exercise.presentation.symbolName),
                            "Unknown SF Symbol \(exercise.presentation.symbolName) for \(exercise.id.rawValue)")
        }
    }

    func testGradientTokensAreUniqueAndHaveValidStops() {
        let presentations = ExerciseCatalog.all.map(\.presentation)
        let tokens = presentations.map(\.gradient.token)
        XCTAssertEqual(Set(tokens).count, tokens.count, "Each exercise needs its own gradient token")

        for (exercise, presentation) in zip(ExerciseCatalog.all, presentations) {
            XCTAssertGreaterThanOrEqual(presentation.gradient.stops.count, 2,
                                        "Gradient needs at least two stops for \(exercise.id.rawValue)")
            for stop in presentation.gradient.stops {
                let hex = stop.hasPrefix("#") ? String(stop.dropFirst()) : stop
                XCTAssertTrue(hex.count == 6 && hex.allSatisfy(\.isHexDigit),
                              "Invalid gradient stop \(stop) for \(exercise.id.rawValue)")
            }
        }
    }

    func testWatchItemsOnlyReferenceThatExercisesCorrectiveCuesAndUseApprovedCopy() {
        let bannedPhrases = ["injury", "pain", "medical", "diagnos", "scoliosis", "posture correction", "cure", "treat"]

        for exercise in ExerciseCatalog.all {
            let correctiveCueIDs = Set(exercise.coachingCues.filter { $0.kind == .corrective }.map(\.id))
            for item in exercise.presentation.watchesFor {
                XCTAssertTrue(correctiveCueIDs.contains(item.cueID),
                              "\(item.cueID.rawValue) is not a corrective cue for \(exercise.id.rawValue)")
                XCTAssertFalse(item.text.hasSuffix("."), "Watch text should not end with a period: \(item.text)")
                XCTAssertLessThanOrEqual(item.text.count, 40, "Watch text is too long: \(item.text)")
                let lowered = item.text.lowercased()
                for bannedPhrase in bannedPhrases {
                    XCTAssertFalse(lowered.contains(bannedPhrase),
                                   "Banned wording '\(bannedPhrase)' in \(item.text)")
                }
            }
        }
    }

    func testFilterGroupsAgreeWithEquipmentAndEveryExerciseHasBodyRegion() {
        for exercise in ExerciseCatalog.all {
            let groups = exercise.presentation.filterGroups
            XCTAssertTrue(groups.contains(.upper) != groups.contains(.lower),
                          "Exercise needs exactly one upper/lower group: \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.dumbbells), exercise.equipment == .dumbbells,
                           "Dumbbell filter does not match equipment for \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.bodyweight), exercise.equipment == .bodyweight,
                           "Bodyweight filter does not match equipment for \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.band), exercise.equipment == .band,
                           "Band filter does not match equipment for \(exercise.id.rawValue)")
        }
    }

    func testLiveCatalogProviderReturnsCatalogInOrderAndLooksUpByID() {
        let provider = LiveExerciseCatalog()
        XCTAssertEqual(provider.all.map(\.id), ExerciseCatalog.all.map(\.id))

        for exercise in ExerciseCatalog.all {
            XCTAssertEqual(provider.exercise(exercise.id)?.id, exercise.id)
        }
        XCTAssertNil(provider.exercise(ExerciseID(rawValue: "not_an_exercise")))
    }
}
