import XCTest
@testable import PostureAnalysisApp

final class PersonaCopyComposerTests: XCTestCase {
    private let key = "achievement.test"

    func testToneAndFamiliarityGating() throws {
        let entry = makeEntry(
            defaultTone: .warm,
            title: [PersonaCopyVariant(text: "Title", tones: [.proud])],
            body: [
                PersonaCopyVariant(text: "Base"),
                PersonaCopyVariant(text: "Familiar", minFamiliarity: .familiar),
                PersonaCopyVariant(text: "Established", minFamiliarity: .established),
                PersonaCopyVariant(text: "Long term", minFamiliarity: .longTerm)
            ]
        )
        let catalog = makeCatalog(entry: entry)

        XCTAssertEqual(compose(catalog, tone: .proud, familiarity: .new)?.content.title, "Title")
        XCTAssertEqual(compose(catalog, tone: .proud, familiarity: .new)?.content.body, "Base")
        XCTAssertEqual(compose(catalog, tone: .proud, familiarity: .familiar, variant: 1)?.content.body, "Familiar")
        XCTAssertEqual(compose(catalog, tone: .proud, familiarity: .established, variant: 2)?.content.body, "Established")
        XCTAssertEqual(compose(catalog, tone: .proud, familiarity: .longTerm, variant: 3)?.content.body, "Long term")
        XCTAssertNil(compose(catalog, tone: .warm, familiarity: .new))

        // Lines above the current familiarity never appear, whatever the variant.
        let newBodies = Set((0..<16).compactMap { compose(catalog, tone: .proud, familiarity: .new, variant: $0)?.content.body })
        XCTAssertEqual(newBodies, ["Base"])
        let familiarBodies = Set((0..<16).compactMap { compose(catalog, tone: .proud, familiarity: .familiar, variant: $0)?.content.body })
        XCTAssertEqual(familiarBodies, ["Base", "Familiar"])
    }

    func testFallsBackToDefaultToneWhenRequestedToneHasNoEligibleCopy() throws {
        let entry = makeEntry(
            defaultTone: .warm,
            title: [PersonaCopyVariant(text: "Warm title", tones: [.warm])],
            body: [PersonaCopyVariant(text: "Warm body", tones: [.warm])]
        )
        let result = try XCTUnwrap(compose(makeCatalog(entry: entry), tone: .smug))

        XCTAssertEqual(result.content.title, "Warm title")
        XCTAssertEqual(result.content.body, "Warm body")
        XCTAssertEqual(result.content.imageAssetName, art.assetName)
    }

    func testUnrenderableLinesAreSkippedAndKeepTheirFullIndices() throws {
        let entry = makeEntry(
            title: [
                PersonaCopyVariant(text: "{missing}"),
                PersonaCopyVariant(text: "Title")
            ],
            body: [
                PersonaCopyVariant(text: "{missing}"),
                PersonaCopyVariant(text: "Body")
            ]
        )
        let result = try XCTUnwrap(compose(makeCatalog(entry: entry)))

        XCTAssertEqual(result.content.title, "Title")
        XCTAssertEqual(result.content.body, "Body")
        XCTAssertEqual(result.templateID, "\(key)#t1b1")
    }

    func testUsesFallbackTitleWhenEligibleTitlesCannotRender() throws {
        let entry = makeEntry(
            title: [PersonaCopyVariant(text: "{missing}")],
            body: [PersonaCopyVariant(text: "Readable body")]
        )
        let result = try XCTUnwrap(compose(makeCatalog(entry: entry)))

        XCTAssertEqual(result.content.title, NotificationContentBuilder.fallbackTitle)
        XCTAssertEqual(result.content.body, "Readable body")
        XCTAssertEqual(result.templateID, "\(key)#tFb0", "tF marks the fallback title")
    }

    func testVariantSelectsTitleAndBodyAndWrapsNegativeValues() throws {
        let entry = makeEntry(
            title: [PersonaCopyVariant(text: "T0"), PersonaCopyVariant(text: "T1")],
            body: [PersonaCopyVariant(text: "B0"), PersonaCopyVariant(text: "B1")]
        )
        let catalog = makeCatalog(entry: entry)
        XCTAssertEqual(compose(catalog, variant: 0)?.content.title, "T0")
        XCTAssertEqual(compose(catalog, variant: 0)?.content.body, "B0")
        XCTAssertEqual(compose(catalog, variant: 1)?.content.title, "T1")
        XCTAssertEqual(compose(catalog, variant: 1)?.content.body, "B0")
        XCTAssertEqual(compose(catalog, variant: 2)?.content.title, "T0")
        XCTAssertEqual(compose(catalog, variant: 2)?.content.body, "B1")
        XCTAssertEqual(compose(catalog, variant: 3)?.content.title, "T1")
        XCTAssertEqual(compose(catalog, variant: 3)?.content.body, "B1")
        XCTAssertEqual(compose(catalog, variant: -1), compose(catalog, variant: 15))
        XCTAssertEqual(compose(catalog, variant: Int.min), compose(catalog, variant: 0))
    }

    func testEveryTitleAndBodyPairMeetsEveryFragmentPattern() throws {
        let entry = makeEntry(
            title: [PersonaCopyVariant(text: "T0"), PersonaCopyVariant(text: "T1")],
            body: [PersonaCopyVariant(text: "B0"), PersonaCopyVariant(text: "B1")]
        )
        let fragments = PersonaFragments(openers: [PersonaCopyVariant(text: "Open.")], closers: [PersonaCopyVariant(text: "Close.")])
        let catalog = makeCatalog(entry: entry, fragments: fragments)
        var seen: [String: Set<String>] = [:]
        for variant in 0..<16 {
            let result = try XCTUnwrap(compose(catalog, variant: variant))
            let pair = "\(result.content.title)/\(result.content.body.replacingOccurrences(of: "Open. ", with: "").replacingOccurrences(of: " Close.", with: ""))"
            let pattern = (result.content.body.hasPrefix("Open.") ? "o" : "") + (result.content.body.hasSuffix("Close.") ? "c" : "")
            seen[pair, default: []].insert(pattern)
        }
        XCTAssertEqual(seen.count, 4)
        XCTAssertTrue(seen.values.allSatisfy { $0 == ["", "o", "c", "oc"] }, "\(seen)")

        // With several openers and closers, every one of them is reachable.
        let wider = makeCatalog(entry: entry, fragments: PersonaFragments(
            openers: [PersonaCopyVariant(text: "Oh."), PersonaCopyVariant(text: "Well.")],
            closers: [PersonaCopyVariant(text: "Noted."), PersonaCopyVariant(text: "Seen."), PersonaCopyVariant(text: "Ha.")]
        ))
        let bodies = (0..<48).compactMap { compose(wider, variant: $0)?.content.body }
        for fragment in ["Oh.", "Well.", "Noted.", "Seen.", "Ha."] {
            XCTAssertTrue(bodies.contains { $0.contains(fragment) }, "\(fragment) never composed")
        }
    }

    func testNegativeToneBelowEstablishedFallsBackToTheDefaultTone() throws {
        let entry = makeEntry(
            defaultTone: .concerned,
            title: [PersonaCopyVariant(text: "Title")],
            body: [PersonaCopyVariant(text: "Neutral")],
            art: [.annoyed: NotificationScenario.Art(expression: "annoyed", outfit: "hoodie", crop: .close)]
        )
        let catalog = makeCatalog(entry: entry)
        let early = try XCTUnwrap(compose(catalog, tone: .annoyed, familiarity: .familiar))
        XCTAssertNotEqual(early.content.imageAssetName, "NotificationCharacter/annoyed-hoodie-close")
        let later = try XCTUnwrap(compose(catalog, tone: .annoyed, familiarity: .established))
        XCTAssertEqual(later.content.imageAssetName, "NotificationCharacter/annoyed-hoodie-close")
    }

    func testFragmentPatternsAndTemplateIdentifiers() throws {
        let entry = makeEntry(title: [PersonaCopyVariant(text: "Title")], body: [PersonaCopyVariant(text: "Body")])
        let fragments = PersonaFragments(
            openers: [PersonaCopyVariant(text: "Open.")],
            closers: [PersonaCopyVariant(text: "Close.")]
        )
        let catalog = makeCatalog(entry: entry, fragments: fragments)
        let expected = ["Body", "Open. Body", "Body Close.", "Open. Body Close."]
        let identifiers = [
            "\(key)#t0b0", "\(key)#t0b0o0", "\(key)#t0b0c0", "\(key)#t0b0o0c0"
        ]

        for variant in 0..<4 {
            let result = try XCTUnwrap(compose(catalog, variant: variant))
            XCTAssertEqual(result.content.body, expected[variant])
            XCTAssertEqual(result.templateID, identifiers[variant])
            XCTAssertEqual(result.content.kind, .persona)
        }
    }

    func testIntroReplacesCloserAndIsIncludedForEveryPattern() throws {
        let entry = makeEntry(title: [PersonaCopyVariant(text: "Title")], body: [PersonaCopyVariant(text: "Body")])
        let fragments = PersonaFragments(
            openers: [PersonaCopyVariant(text: "Open.")],
            closers: [PersonaCopyVariant(text: "Close.")],
            intro: [PersonaCopyVariant(text: "Intro.")]
        )
        let catalog = makeCatalog(entry: entry, fragments: fragments)
        let expectedBodies = ["Body Intro.", "Open. Body Intro.", "Body Intro.", "Open. Body Intro."]
        let expectedIDs = ["i0", "o0i0", "i0", "o0i0"]

        for variant in 0..<4 {
            let result = try XCTUnwrap(compose(catalog, variant: variant, intro: true))
            XCTAssertEqual(result.content.body, expectedBodies[variant])
            XCTAssertEqual(result.templateID, "\(key)#t0b0\(expectedIDs[variant])")
        }
    }

    func testLengthTrimmingDropsCloserBeforeOpenerAndKeepsIntroWhenOpenerCanBeDropped() throws {
        let normalEntry = makeEntry(
            title: [PersonaCopyVariant(text: "Title")],
            body: [PersonaCopyVariant(text: String(repeating: "b", count: 104))]
        )
        let normalCatalog = makeCatalog(
            entry: normalEntry,
            fragments: PersonaFragments(
                openers: [PersonaCopyVariant(text: "Hi.")],
                closers: [PersonaCopyVariant(text: "Bye.")]
            )
        )
        let normal = try XCTUnwrap(compose(normalCatalog, variant: 3))
        XCTAssertEqual(normal.content.body.count, 108)
        XCTAssertTrue(normal.templateID.hasSuffix("o0"))

        let introEntry = makeEntry(
            title: [PersonaCopyVariant(text: "Title")],
            body: [PersonaCopyVariant(text: String(repeating: "b", count: 102))]
        )
        let introCatalog = makeCatalog(
            entry: introEntry,
            fragments: PersonaFragments(
                openers: [PersonaCopyVariant(text: "Hi.")],
                intro: [PersonaCopyVariant(text: "Intro!")]
            )
        )
        let introResult = try XCTUnwrap(compose(introCatalog, variant: 1, intro: true))
        XCTAssertEqual(introResult.content.body, "\(String(repeating: "b", count: 102)) Intro!")
        XCTAssertEqual(introResult.templateID, "\(key)#t0b0i0")
        XCTAssertLessThanOrEqual(introResult.content.body.count, PersonaCopyComposer.maximumBodyLength)
    }

    func testTemplateRenderingAndTokenOrder() {
        XCTAssertEqual(PersonaTemplate.render("{first} then {second}", values: ["first": "one", "second": "two"]), "one then two")
        XCTAssertNil(PersonaTemplate.render("{missing}", values: [:]))
        XCTAssertNil(PersonaTemplate.render("{value} reps", values: ["value": ""]), "an empty value counts as missing")
        XCTAssertNil(PersonaTemplate.render("Unclosed {token", values: ["token": "value"]))
        XCTAssertNil(PersonaTemplate.render("Stray }", values: [:]))
        XCTAssertEqual(PersonaTemplate.tokens(in: "{first} and {second} then {first}"), ["first", "second", "first"])
    }

    func testVariantCountUsesSampleValues() throws {
        let entry = makeEntry(
            tokens: ["sample"],
            sample: ["sample": "value"],
            title: [PersonaCopyVariant(text: "{sample}"), PersonaCopyVariant(text: "{runtime}")],
            body: [PersonaCopyVariant(text: "{sample}")]
        )
        let count = PersonaCopyComposer.variantCount(
            catalog: makeCatalog(entry: entry),
            contentKey: key,
            tone: .warm,
            familiarity: .new
        )
        XCTAssertEqual(count, 1)
    }

    func testEveryBundledKeyComposesForEveryToneFamiliarityAndIntroChoice() throws {
        let catalog = try PersonaContentCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))

        for key in catalog.contentKeys {
            guard let entry = catalog.entry(key) else { return XCTFail("Missing entry \(key)") }
            for tone in PersonaTone.allCases {
                for familiarity in PersonaFamiliarity.allCases {
                    for intro in [false, true] {
                        let result = PersonaCopyComposer.compose(
                            catalog: catalog,
                            contentKey: key,
                            tone: tone,
                            familiarity: familiarity,
                            values: entry.sample,
                            variant: 17,
                            intro: intro
                        )
                        XCTAssertNotNil(result, "\(key), \(tone), \(familiarity), intro=\(intro)")
                        XCTAssertLessThanOrEqual(result?.content.body.count ?? Int.max, PersonaCopyComposer.maximumBodyLength)
                        XCTAssertFalse(result?.content.body.contains("{") ?? true)
                        XCTAssertFalse(result?.content.body.contains("}") ?? true)
                    }
                }
            }
        }
    }

    private var art: NotificationScenario.Art {
        NotificationScenario.Art(expression: "smile", outfit: "hoodie", crop: .portrait)
    }

    private func makeEntry(
        defaultTone: PersonaTone = .warm,
        tokens: [String] = [],
        sample: [String: String] = [:],
        title: [PersonaCopyVariant],
        body: [PersonaCopyVariant],
        art overrides: [PersonaTone: NotificationScenario.Art] = [:]
    ) -> PersonaContentEntry {
        PersonaContentEntry(
            key: key,
            family: .achievement,
            defaultTone: defaultTone,
            tokens: tokens,
            sample: sample,
            title: title,
            body: body,
            art: overrides
        )
    }

    private func makeCatalog(entry: PersonaContentEntry, fragments: PersonaFragments = PersonaFragments()) -> PersonaContentCatalog {
        PersonaContentCatalog(
            toneArt: Dictionary(uniqueKeysWithValues: PersonaTone.allCases.map { ($0, art) }),
            fragments: fragments,
            entries: [key: entry]
        )
    }

    private func compose(
        _ catalog: PersonaContentCatalog,
        tone: PersonaTone = .warm,
        familiarity: PersonaFamiliarity = .new,
        values: [String: String] = [:],
        variant: Int = 0,
        intro: Bool = false
    ) -> PersonaComposition? {
        PersonaCopyComposer.compose(
            catalog: catalog,
            contentKey: key,
            tone: tone,
            familiarity: familiarity,
            values: values,
            variant: variant,
            intro: intro
        )
    }
}
