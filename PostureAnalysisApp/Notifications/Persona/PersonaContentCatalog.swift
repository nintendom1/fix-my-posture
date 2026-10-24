import Foundation

/// One authored line: a title, a body, or a fragment. `tones` and `minFamiliarity` gate when it may be used;
/// nil means any tone or any familiarity.
struct PersonaCopyVariant: Codable, Equatable {
    let text: String
    let tones: [PersonaTone]?
    let minFamiliarity: PersonaFamiliarity?

    init(text: String, tones: [PersonaTone]? = nil, minFamiliarity: PersonaFamiliarity? = nil) {
        self.text = text
        self.tones = tones
        self.minFamiliarity = minFamiliarity
    }

    /// Usable for this tone at this familiarity.
    func isEligible(tone: PersonaTone, familiarity: PersonaFamiliarity) -> Bool {
        (tones?.contains(tone) ?? true) && familiarity >= (minFamiliarity ?? .new)
    }
}

/// Short reusable pieces composed around a body so a small authored set reads naturally.
struct PersonaFragments: Codable, Equatable {
    /// Placed before the body, such as "Okay."
    let openers: [PersonaCopyVariant]
    /// Placed after the body, such as "Noted."
    let closers: [PersonaCopyVariant]
    /// Placed after the body instead of a closer on the first persona message after install or reset.
    let intro: [PersonaCopyVariant]

    init(openers: [PersonaCopyVariant] = [], closers: [PersonaCopyVariant] = [], intro: [PersonaCopyVariant] = []) {
        self.openers = openers
        self.closers = closers
        self.intro = intro
    }
}

/// One content key's copy and art, such as `achievement.pr.weight`.
struct PersonaContentEntry: Equatable {
    let key: String
    let family: ObservationFamily
    /// Used when no title or body is eligible for the selected tone.
    let defaultTone: PersonaTone
    /// Token names this entry's copy may use.
    let tokens: [String]
    /// Sample token values for the developer preview.
    let sample: [String: String]
    let title: [PersonaCopyVariant]
    let body: [PersonaCopyVariant]
    /// Per-tone art overrides; tones without one use the catalog's `toneArt`.
    let art: [PersonaTone: NotificationScenario.Art]
}

enum PersonaContentCatalogError: Error, Equatable {
    case missingDataAsset
    case invalid(String)
}

/// Decoded `persona-content.json` (bundled as the `PersonaContent` data asset). The JSON file in
/// Design/NotificationCharacter is the single hand-edited source of truth for persona wording and art.
struct PersonaContentCatalog: Equatable {
    static let dataAssetName = "PersonaContent"
    static let supportedVersion = 1

    /// Default art for each tone.
    let toneArt: [PersonaTone: NotificationScenario.Art]
    let fragments: PersonaFragments
    let entries: [String: PersonaContentEntry]

    init(toneArt: [PersonaTone: NotificationScenario.Art], fragments: PersonaFragments, entries: [String: PersonaContentEntry]) {
        self.toneArt = toneArt
        self.fragments = fragments
        self.entries = entries
    }

    private struct Document: Decodable {
        let version: Int
        let sampleValues: [String: String]
        let tokens: [String: String]
        let reservedTokens: [String]
        let tones: [String]
        let familiarities: [String]
        let toneArt: [String: RawArt]
        let fragments: RawFragments
        let content: [String: RawEntry]
    }

    private struct RawArt: Decodable {
        let expression: String
        let outfit: String
        let crop: String
    }

    private struct RawFragments: Decodable {
        let openers: [RawVariant]
        let closers: [RawVariant]
        let intro: [RawVariant]
    }

    private struct RawVariant: Decodable {
        let text: String
        let tones: [String]?
        let minFamiliarity: String?
    }

    private struct RawEntry: Decodable {
        let family: String
        let defaultTone: String
        let tokens: [String]
        let title: [RawVariant]
        let body: [RawVariant]
        let art: [String: RawArt]
    }

    /// Decodes and checks the JSON: supported version, every tone has art, at least one title and body per entry,
    /// known tones and familiarities, entry keys unique and matching their `family` prefix. Throws `.invalid`.
    init(data: Data) throws {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw PersonaContentCatalogError.invalid(error.localizedDescription)
        }
        guard document.version == Self.supportedVersion else {
            throw PersonaContentCatalogError.invalid("unsupported version \(document.version)")
        }

        for tone in document.tones {
            _ = try Self.tone(tone, context: "tones")
        }
        for familiarity in document.familiarities {
            _ = try Self.familiarity(familiarity, context: "familiarities")
        }

        var decodedToneArt: [PersonaTone: NotificationScenario.Art] = [:]
        for (rawTone, rawArt) in document.toneArt {
            let tone = try Self.tone(rawTone, context: "toneArt")
            decodedToneArt[tone] = try Self.art(rawArt, context: "toneArt[\(rawTone)]")
        }
        for tone in PersonaTone.allCases where decodedToneArt[tone] == nil {
            throw PersonaContentCatalogError.invalid("missing tone art for \(tone.rawValue)")
        }

        let decodedFragments = PersonaFragments(
            openers: try document.fragments.openers.map { try Self.variant($0, context: "fragments.openers") },
            closers: try document.fragments.closers.map { try Self.variant($0, context: "fragments.closers") },
            intro: try document.fragments.intro.map { try Self.variant($0, context: "fragments.intro") }
        )

        var decodedEntries: [String: PersonaContentEntry] = [:]
        for key in document.content.keys.sorted() {
            guard let rawEntry = document.content[key] else { continue }
            guard let family = ObservationFamily(rawValue: rawEntry.family) else {
                throw PersonaContentCatalogError.invalid("unknown family '\(rawEntry.family)' for \(key)")
            }
            let keyFamily = key.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard family.rawValue == keyFamily else {
                throw PersonaContentCatalogError.invalid("family mismatch for \(key): expected \(keyFamily), got \(family.rawValue)")
            }
            let defaultTone = try Self.tone(rawEntry.defaultTone, context: "content[\(key)].defaultTone")
            guard !rawEntry.title.isEmpty else {
                throw PersonaContentCatalogError.invalid("entry \(key) has no title")
            }
            guard !rawEntry.body.isEmpty else {
                throw PersonaContentCatalogError.invalid("entry \(key) has no body")
            }

            var decodedArt: [PersonaTone: NotificationScenario.Art] = [:]
            for (rawTone, rawArt) in rawEntry.art {
                let tone = try Self.tone(rawTone, context: "content[\(key)].art")
                decodedArt[tone] = try Self.art(rawArt, context: "content[\(key)].art[\(rawTone)]")
            }
            let tokenNames = Set(rawEntry.tokens)
            let sample = document.sampleValues.filter { tokenNames.contains($0.key) }
            decodedEntries[key] = PersonaContentEntry(
                key: key,
                family: family,
                defaultTone: defaultTone,
                tokens: rawEntry.tokens,
                sample: sample,
                title: try rawEntry.title.map { try Self.variant($0, context: "content[\(key)].title") },
                body: try rawEntry.body.map { try Self.variant($0, context: "content[\(key)].body") },
                art: decodedArt
            )
        }

        toneArt = decodedToneArt
        fragments = decodedFragments
        entries = decodedEntries
    }

    private static func tone(_ rawValue: String, context: String) throws -> PersonaTone {
        guard let value = PersonaTone(rawValue: rawValue) else {
            throw PersonaContentCatalogError.invalid("unknown tone '\(rawValue)' in \(context)")
        }
        return value
    }

    private static func familiarity(_ rawValue: String, context: String) throws -> PersonaFamiliarity {
        guard let value = PersonaFamiliarity(rawValue: rawValue) else {
            throw PersonaContentCatalogError.invalid("unknown familiarity '\(rawValue)' in \(context)")
        }
        return value
    }

    private static func art(_ rawArt: RawArt, context: String) throws -> NotificationScenario.Art {
        guard let crop = NotificationScenario.Crop(rawValue: rawArt.crop) else {
            throw PersonaContentCatalogError.invalid("unknown crop '\(rawArt.crop)' in \(context)")
        }
        return NotificationScenario.Art(expression: rawArt.expression, outfit: rawArt.outfit, crop: crop)
    }

    private static func variant(_ rawVariant: RawVariant, context: String) throws -> PersonaCopyVariant {
        let tones = try rawVariant.tones?.map { try Self.tone($0, context: context) }
        let familiarity = try rawVariant.minFamiliarity.map { try Self.familiarity($0, context: context) }
        return PersonaCopyVariant(text: rawVariant.text, tones: tones, minFamiliarity: familiarity)
    }

    var contentKeys: [String] { entries.keys.sorted() }

    func entry(_ key: String) -> PersonaContentEntry? { entries[key] }

    /// The entry's art override for `tone`, else the tone's default art.
    func art(for contentKey: String, tone: PersonaTone) -> NotificationScenario.Art? {
        entries[contentKey]?.art[tone] ?? toneArt[tone]
    }
}
