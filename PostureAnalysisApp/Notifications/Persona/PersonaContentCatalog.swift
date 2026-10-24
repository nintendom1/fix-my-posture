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

    /// Decodes and checks the JSON: supported version, every tone has art, at least one title and body per entry,
    /// known tones and familiarities, entry keys unique and matching their `family` prefix. Throws `.invalid`.
    init(data: Data) throws {
        // Implemented by P4.
        throw PersonaContentCatalogError.invalid("not implemented")
    }

    var contentKeys: [String] { entries.keys.sorted() }

    func entry(_ key: String) -> PersonaContentEntry? { entries[key] }

    /// The entry's art override for `tone`, else the tone's default art.
    func art(for contentKey: String, tone: PersonaTone) -> NotificationScenario.Art? {
        entries[contentKey]?.art[tone] ?? toneArt[tone]
    }
}
