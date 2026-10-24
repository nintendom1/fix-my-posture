import Foundation

/// A composed persona message and the template choices that produced it (for the decision trace).
struct PersonaComposition: Equatable {
    let content: CharacterNotificationContent
    /// `contentKey#t<titleIndex>b<bodyIndex>` plus `o<index>` for an opener and `c<index>` or `i<index>` for a closer
    /// or intro fragment, such as `achievement.pr.weight#t0b1o2`.
    let templateID: String
}

/// Builds persona copy from structured facts: content key, tone, familiarity, token values, and a variant number.
/// No business logic lives in strings and no copy lives in Swift.
enum PersonaCopyComposer {
    private struct RenderedLine {
        let index: Int
        let text: String
    }

    private struct ToneSelection {
        let tone: PersonaTone
        let titles: [RenderedLine]
        let bodies: [RenderedLine]
        let fallbackTitleIndex: Int?

        var titleCount: Int { titles.isEmpty ? 1 : titles.count }
    }

    private enum TrailingFragment {
        case closer(RenderedLine)
        case intro(RenderedLine)

        var line: RenderedLine {
            switch self {
            case .closer(let line), .intro(let line): line
            }
        }
    }

    /// Eligible titles and bodies are those whose tones include `tone` (or are untagged) and whose
    /// `minFamiliarity` is at or below `familiarity`. If none are eligible for `tone`, the entry's `defaultTone` is
    /// used. `variant` (any integer, wrapped) picks the title, the body, and the fragment pattern: `variant % 4` is
    /// none, opener, closer, or both, using only eligible fragments that keep the body within the length limit.
    /// When `intro` is true an intro fragment replaces the closer. Art is `catalog.art(for:tone:)` with the tone
    /// actually used. Lines whose tokens cannot be filled are skipped; nil when nothing can be composed.
    /// The result's `content.kind` is `.persona` and `content.scenarioID` is the content key.
    static func compose(
        catalog: PersonaContentCatalog,
        contentKey: String,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity,
        values: [String: String],
        variant: Int,
        intro: Bool
    ) -> PersonaComposition? {
        guard let entry = catalog.entry(contentKey),
              let selection = selectTone(
                entry: entry,
                requestedTone: tone,
                familiarity: familiarity,
                values: values
              ) else {
            return nil
        }

        let titleCount = selection.titleCount
        let combinationCount = product(titleCount, selection.bodies.count)
        guard combinationCount > 0 else { return nil }
        let v = normalizedVariant(variant, combinationCount: combinationCount)
        let combination = v % combinationCount
        let titleLine = selection.titles.isEmpty ? nil : selection.titles[combination % titleCount]
        let title = titleLine?.text ?? NotificationContentBuilder.fallbackTitle
        let titleIndex = titleLine?.index ?? selection.fallbackTitleIndex ?? 0
        let bodyLine = selection.bodies[combination / titleCount]

        let fragments = catalog.fragments
        let openers = renderedLines(fragments.openers, tone: selection.tone, familiarity: familiarity, values: values)
        let closers = renderedLines(fragments.closers, tone: selection.tone, familiarity: familiarity, values: values)
        let intros = renderedLines(fragments.intro, tone: selection.tone, familiarity: familiarity, values: values)
        let pattern = v % 4
        var opener: RenderedLine? = (pattern == 1 || pattern == 3) ? selectedLine(openers, variant: v) : nil
        var trailing: TrailingFragment?
        let selectedIntro = intro ? selectedLine(intros, variant: v) : nil
        if let selectedIntro {
            trailing = .intro(selectedIntro)
        } else if pattern == 2 || pattern == 3 {
            trailing = selectedLine(closers, variant: v).map(TrailingFragment.closer)
        }

        if bodyLength(opener: opener, body: bodyLine.text, trailing: trailing) > maximumBodyLength {
            if case .intro? = trailing {
                opener = nil
                if bodyLength(opener: opener, body: bodyLine.text, trailing: trailing) > maximumBodyLength {
                    trailing = nil
                }
            } else {
                trailing = nil
                if bodyLength(opener: opener, body: bodyLine.text, trailing: trailing) > maximumBodyLength {
                    opener = nil
                }
            }
        }

        let body = joinedBody(opener: opener, body: bodyLine.text, trailing: trailing)
        guard let art = catalog.art(for: contentKey, tone: selection.tone) else { return nil }

        var templateID = "\(contentKey)#t\(titleIndex)b\(bodyLine.index)"
        if let opener { templateID += "o\(opener.index)" }
        switch trailing {
        case .closer(let line): templateID += "c\(line.index)"
        case .intro(let line): templateID += "i\(line.index)"
        case nil: break
        }

        return PersonaComposition(
            content: CharacterNotificationContent(
                scenarioID: contentKey,
                kind: .persona,
                title: title,
                body: body,
                imageAssetName: art.assetName,
                artLabel: art.label
            ),
            templateID: templateID
        )
    }

    /// How many distinct title × body combinations are eligible, for the developer preview's variant stepper.
    static func variantCount(
        catalog: PersonaContentCatalog,
        contentKey: String,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity
    ) -> Int {
        guard let entry = catalog.entry(contentKey),
              let selection = selectTone(
                entry: entry,
                requestedTone: tone,
                familiarity: familiarity,
                values: entry.sample
              ) else {
            return 0
        }
        return product(selection.titleCount, selection.bodies.count)
    }

    /// Longest composed body allowed, matching the scenario copy limit.
    static let maximumBodyLength = 110

    private static func selectTone(
        entry: PersonaContentEntry,
        requestedTone: PersonaTone,
        familiarity: PersonaFamiliarity,
        values: [String: String]
    ) -> ToneSelection? {
        selection(entry: entry, tone: requestedTone, familiarity: familiarity, values: values)
            ?? selection(entry: entry, tone: entry.defaultTone, familiarity: familiarity, values: values)
    }

    private static func selection(
        entry: PersonaContentEntry,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity,
        values: [String: String]
    ) -> ToneSelection? {
        let titles = renderedLines(entry.title, tone: tone, familiarity: familiarity, values: values)
        let bodies = renderedLines(entry.body, tone: tone, familiarity: familiarity, values: values)
        guard !bodies.isEmpty else { return nil }
        let fallbackTitleIndex = titles.isEmpty
            ? entry.title.firstIndex { $0.isEligible(tone: tone, familiarity: familiarity) }
            : nil
        guard !titles.isEmpty || fallbackTitleIndex != nil else { return nil }
        return ToneSelection(tone: tone, titles: titles, bodies: bodies, fallbackTitleIndex: fallbackTitleIndex)
    }

    private static func renderedLines(
        _ variants: [PersonaCopyVariant],
        tone: PersonaTone,
        familiarity: PersonaFamiliarity,
        values: [String: String]
    ) -> [RenderedLine] {
        variants.enumerated().compactMap { index, line in
            guard line.isEligible(tone: tone, familiarity: familiarity),
                  let text = PersonaTemplate.render(line.text, values: values) else {
                return nil
            }
            return RenderedLine(index: index, text: text)
        }
    }

    private static func selectedLine(_ lines: [RenderedLine], variant: Int) -> RenderedLine? {
        guard !lines.isEmpty else { return nil }
        return lines[variant % lines.count]
    }

    private static func normalizedVariant(_ variant: Int, combinationCount: Int) -> Int {
        let (cycle, overflow) = combinationCount.multipliedReportingOverflow(by: 4)
        let period = overflow ? Int.max : cycle
        let remainder = variant % period
        return remainder < 0 ? remainder + period : remainder
    }

    private static func product(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? Int.max : value
    }

    private static func bodyLength(opener: RenderedLine?, body: String, trailing: TrailingFragment?) -> Int {
        joinedBody(opener: opener, body: body, trailing: trailing).count
    }

    private static func joinedBody(opener: RenderedLine?, body: String, trailing: TrailingFragment?) -> String {
        [opener?.text, body, trailing?.line.text]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
