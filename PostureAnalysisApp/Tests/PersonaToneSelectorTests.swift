import XCTest
@testable import PostureAnalysisApp

final class PersonaToneSelectorTests: XCTestCase {
    func testEveryPreferenceRow() {
        let cases: [(String, PersonaFamiliarity, PersonaTrajectory, [PersonaTone])] = [
            ("achievement.pr.weight", .new, .stable, [.proud, .pleased]),
            ("achievement.pr.reps", .familiar, .stable, [.proud, .pleased]),
            ("achievement.pr.weight", .established, .stable, [.smug, .competitive, .proud]),
            ("achievement.pr.reps", .longTerm, .stable, [.smug, .competitive, .proud]),
            ("achievement.milestone", .new, .unknown, [.proud, .pleased, .warm]),
            ("pattern.weekday", .new, .stable, [.pleased, .warm]),
            ("pattern.routineRepeat", .familiar, .improving, [.pleased, .warm]),
            ("pattern.timeOfDay", .established, .stable, [.smug, .pleased]),
            ("pattern.weekday", .longTerm, .declining, [.warm, .pleased]),
            ("lapse.skippedExercise", .new, .stable, [.concerned]),
            ("lapse.skippedExercise", .familiar, .stable, [.concerned, .warm]),
            ("lapse.skippedExercise", .established, .stable, [.annoyed, .smug, .concerned]),
            ("lapse.skippedExercise", .longTerm, .declining, [.annoyed, .smug, .concerned]),
            ("lapse.neglectedRoutine", .new, .stable, [.concerned]),
            ("lapse.neglectedRoutine", .familiar, .declining, [.concerned]),
            ("lapse.neglectedRoutine", .established, .stable, [.annoyed, .concerned]),
            ("lapse.neglectedRoutine", .longTerm, .declining, [.disappointed, .concerned]),
            ("lapse.decliningWeeks", .established, .declining, [.concerned]),
            ("lapse.decliningWeeks", .longTerm, .declining, [.disappointed, .concerned]),
            ("lapse.comeback", .new, .unknown, [.warm]),
            ("lapse.comeback", .familiar, .stable, [.relieved, .warm]),
            ("posture.returned", .new, .stable, [.pleased, .warm]),
            ("posture.improved", .longTerm, .improving, [.pleased, .warm]),
            ("posture.futureKind", .established, .stable, [.pleased, .warm]),
            ("achievement.futureKind", .established, .stable, [.pleased]),
        ]

        for (key, familiarity, trajectory, expected) in cases {
            XCTAssertEqual(
                PersonaToneSelector.preferences(
                    for: observation(key), familiarity: familiarity, trajectory: trajectory
                ),
                expected,
                key
            )
        }
    }

    func testNegativeTonesAreBlockedBelowEstablishedFamiliarity() {
        let lapse = observation("lapse.skippedExercise")
        for familiarity in [PersonaFamiliarity.new, .familiar] {
            let recentToneSets: [[PersonaTone]] = [[], [.annoyed], [.disappointed, .smug]]
            for recentTones in recentToneSets {
                let selected = PersonaToneSelector.tone(
                    for: lapse,
                    familiarity: familiarity,
                    trajectory: .stable,
                    recentTones: recentTones
                )
                XCTAssertFalse(selected.isNegative)
            }
        }
    }

    func testToneRotationAvoidsMostRecentAndExcessivelyRepeatedTone() {
        let pr = observation("achievement.pr.weight")
        XCTAssertEqual(
            PersonaToneSelector.tone(
                for: pr, familiarity: .new, trajectory: .stable, recentTones: [.proud]
            ),
            .pleased
        )

        var policy = PersonaPolicy.standard
        policy.maximumRepeatsOfTone = 0
        XCTAssertEqual(
            PersonaToneSelector.tone(
                for: pr, familiarity: .new, trajectory: .stable,
                recentTones: [.pleased, .proud], policy: policy
            ),
            .proud,
            "Falls back to the first preference when every option exceeds the repeat limit."
        )
    }

    func testToneMayRepeatOnceWhenItIsNotTheMostRecent() {
        let pr = observation("achievement.pr.weight")
        XCTAssertEqual(
            PersonaToneSelector.tone(
                for: pr, familiarity: .new, trajectory: .stable, recentTones: [.pleased, .proud]
            ),
            .proud
        )
    }

    private func observation(_ contentKey: String) -> PersonaObservation {
        let parts = contentKey.split(separator: ".", maxSplits: 1).map(String.init)
        let family = ObservationFamily(rawValue: parts.first ?? "") ?? .achievement
        return PersonaFixtures.observation(
            family,
            parts.count > 1 ? parts[1] : "unknown",
            salience: .medium
        )
    }
}
