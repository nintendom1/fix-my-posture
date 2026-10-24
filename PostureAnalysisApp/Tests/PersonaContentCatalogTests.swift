import UIKit
import XCTest
@testable import PostureAnalysisApp

final class PersonaContentCatalogTests: XCTestCase {
    private let appBundle = Bundle(for: AppEnvironment.self)

    func testDecodesInlineFixtureAndFiltersSamplesToEntryTokens() throws {
        let catalog = try PersonaContentCatalog(data: fixture())
        let entry = try XCTUnwrap(catalog.entry("achievement.test"))

        XCTAssertEqual(entry.sample, ["exercise": "Rows"])
        XCTAssertEqual(entry.family, .achievement)
        XCTAssertEqual(entry.defaultTone, .pleased)
        XCTAssertEqual(catalog.toneArt[.proud]?.crop, .portrait)
    }

    func testRejectsWrongVersionAndUnknownTone() {
        assertInvalid(fixture(version: 2))
        assertInvalid(fixture(title: #"[{"text":"Title", "tones":["mysterious"]}]"#))
    }

    func testRejectsMissingToneArtEmptyBodyAndFamilyMismatch() {
        assertInvalid(fixture(toneNames: PersonaTone.allCases.dropLast().map(\.rawValue)))
        assertInvalid(fixture(body: "[]"))
        assertInvalid(fixture(family: "pattern"))
    }

    func testRejectsUnknownCropAndFamiliarity() {
        assertInvalid(fixture(crop: "square"))
        assertInvalid(fixture(title: #"[{"text":"Title", "minFamiliarity":"forever"}]"#))
    }

    func testToneSpecificArtOverridesDefaultArt() throws {
        let catalog = try PersonaContentCatalog(data: fixture(entryArt: #"{"competitive":{"expression":"shocked","outfit":"hoodie","crop":"close"}}"#))

        XCTAssertEqual(catalog.art(for: "achievement.test", tone: .competitive)?.assetName,
                       "NotificationCharacter/shocked-hoodie-close")
        XCTAssertEqual(catalog.art(for: "achievement.test", tone: .warm)?.assetName,
                       "NotificationCharacter/smile-hoodie-portrait")
        // Unknown keys fall back to the tone's default art; the composer rejects unknown keys before asking for art.
        XCTAssertEqual(catalog.art(for: "missing.key", tone: .warm)?.assetName,
                       "NotificationCharacter/smile-hoodie-portrait")
    }

    func testBundledCatalogContainsEveryPersonaKeyAndItsArtAssetsExist() throws {
        let catalog = try PersonaContentCatalog.bundled(bundle: appBundle)

        XCTAssertEqual(Set(catalog.contentKeys), Set(PersonaFixtures.contentKeys))
        let allArt = Array(catalog.toneArt.values) + catalog.entries.values.flatMap { $0.art.values }
        for art in allArt {
            let image = UIImage(named: art.assetName, in: appBundle, compatibleWith: nil)
            XCTAssertNotNil(image, "Missing bundled persona art \(art.assetName)")
        }
    }

    private func assertInvalid(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PersonaContentCatalog(data: data), file: file, line: line) { error in
            guard case PersonaContentCatalogError.invalid = error else {
                return XCTFail("Expected invalid catalog error, got \(error)", file: file, line: line)
            }
        }
    }

    private func fixture(
        version: Int = PersonaContentCatalog.supportedVersion,
        toneNames: [String] = PersonaTone.allCases.map(\.rawValue),
        crop: String = "portrait",
        family: String = "achievement",
        title: String = #"[{"text":"Title {exercise}"}]"#,
        body: String = #"[{"text":"Body {exercise}"}]"#,
        entryArt: String = "{}"
    ) -> Data {
        let toneList = toneNames.map { "\"\($0)\"" }.joined(separator: ",")
        let toneArt = toneNames.map {
            "\"\($0)\":{\"expression\":\"smile\",\"outfit\":\"hoodie\",\"crop\":\"\(crop)\"}"
        }.joined(separator: ",")
        let json = """
        {
          "version": \(version),
          "sampleValues": {"exercise":"Rows", "unused":"ignored"},
          "tokens": {"exercise":"Exercise name"},
          "reservedTokens": [],
          "tones": [\(toneList)],
          "familiarities": ["new", "familiar", "established", "longTerm"],
          "toneArt": {\(toneArt)},
          "fragments": {"openers":[], "closers":[], "intro":[]},
          "content": {
            "achievement.test": {
              "family":"\(family)", "defaultTone":"pleased", "tokens":["exercise"],
              "title":\(title), "body":\(body), "art":\(entryArt)
            }
          }
        }
        """
        return Data(json.utf8)
    }
}
