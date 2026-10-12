import XCTest
@testable import PostureAnalysisApp

final class WorkoutHistoryTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()
    private let reliable = FramingStatus(isReliable: true, guidance: nil)

    func testWeightsCarryToLaterSetsUntilChanged() throws {
        var session = WorkoutSession(exercises: [press], initialExercise: press.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        _ = session.handle(.command(.start), at: 2)
        let spoken = session.handle(.command(.setWeight(.mass(17.5, .pounds))), at: 3)
        XCTAssertEqual(spoken, [.speak(Utterance(text: "17.5 pounds.", isInstruction: false))], "Heard weights are confirmed out loud.")
        _ = session.handle(.command(.nextSet), at: 4)
        _ = session.handle(.command(.start), at: 100)
        _ = session.handle(.command(.nextSet), at: 101)
        let record = try XCTUnwrap(WorkoutRecord(session: session, startedAt: Date(), endedAt: Date()))
        XCTAssertEqual(record.entries.first?.sets.map(\.weight), [.mass(17.5, .pounds), .mass(17.5, .pounds)],
                       "The next set uses the same weight.")
    }

    func testBodyweightExercisesTakeNoWeight() {
        let squat = AirSquatExercise.definition()
        var session = WorkoutSession(exercises: [squat], initialExercise: squat.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.setWeight(.mass(10, .kilograms))), at: 1)
        XCTAssertTrue(session.currentWeights.isEmpty)
    }

    func testSavedSetRecordsEachOccurrenceWithItsOutcome() throws {
        let curl = HammerCurlExercise.definition()
        let plan = WorkoutPlan(name: "Upper Body", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 1, targetReps: 2...2),
            WorkoutPlanItem(id: UUID(), exerciseID: curl.id, sets: 1, targetReps: 10...10)
        ])
        var session = WorkoutSession(exercises: [press, curl], initialExercise: nil, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.setWeight(.mass(8, .kilograms))), at: 2.5)
        for time in 3...4 {
            _ = session.handle(.repCompleted(RepEvent(epoch: session.analyzerEpoch, timestamp: 0, sides: [.left, .right])), at: Double(time))
        }
        _ = session.handle(.command(.nextExercise), at: 5)
        let record = try XCTUnwrap(WorkoutRecord(session: session, startedAt: Date(), endedAt: Date()))
        XCTAssertEqual(record.planName, "Upper Body")
        XCTAssertEqual(record.entries.map(\.outcome), [.completed, .skipped])
        XCTAssertEqual(record.entries.first?.sets, [RecordedSet(reps: 2, side: nil, weight: .mass(8, .kilograms))])
        XCTAssertEqual(WorkoutRecordEntity(record).value, record, "Survives storage.")
    }

    func testOneArmSetsAreLabeledAndNothingDoneSavesNothing() throws {
        let row = DumbbellRowExercise.definition()
        var session = WorkoutSession(exercises: [row], initialExercise: row.id)
        XCTAssertNil(WorkoutRecord(session: session, startedAt: Date(), endedAt: Date()), "No sets, no history.")
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        _ = session.handle(.command(.start), at: 4)
        _ = session.handle(.command(.nextSet), at: 5)
        let record = try XCTUnwrap(WorkoutRecord(session: session, startedAt: Date(), endedAt: Date()))
        XCTAssertEqual(record.entries.first?.sets.map(\.side), ["L", "R"])
    }
}
