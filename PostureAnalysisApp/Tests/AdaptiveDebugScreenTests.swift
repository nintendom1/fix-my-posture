import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

final class AdaptiveDebugScreenTests: XCTestCase {
    @MainActor
    func testEmptyAdaptiveDebugScreenRendersWithoutAProvider() throws {
        let viewModel = AdaptiveDebugViewModel(provider: nil, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone)

        _ = try SnapshotHost.render(AdaptiveDebugScreen(viewModel: viewModel),
                                    frameId: "adaptive-debug-empty", testCase: self)
    }

    @MainActor
    func testPopulatedAdaptiveDebugScreenRendersSnapshotAndEvidence() async throws {
        let snapshot = makeSnapshot()
        let viewModel = AdaptiveDebugViewModel(provider: FakeAdaptiveDebugProvider(snapshot: snapshot),
                                               now: { FixedClock.date }, timeZone: FixedClock.timeZone)
        await viewModel.refresh()

        _ = try SnapshotHost.render(AdaptiveDebugScreen(viewModel: viewModel),
                                    frameId: "adaptive-debug-populated", testCase: self)
    }

    @MainActor
    private func makeSnapshot() -> AdaptiveSnapshot {
        let variant = VariantID(rawValue: "push.wall_push_up")
        let calibration = CalibrationSessionRecord(
            id: UUID(), kind: .initial, startedAt: FixedClock.date.addingTimeInterval(-3_600),
            endedAt: FixedClock.date.addingTimeInterval(-1_800), status: .committed, families: [.push],
            startingPoints: [CalibrationStart(family: .push,
                                              start: RungDose(variant: variant, dose: .reps(3)))]
        )
        let evidence = AdaptiveEvidence(
            id: UUID(), recordedAt: FixedClock.date, source: .adaptive, family: .push, variant: variant,
            prescribed: .reps(3), confirmed: .reps(0), confirmation: .user,
            tracker: TrackerObservation(status: .lowConfidence, observed: .reps(0),
                                        rejectionReasons: ["trackingGap"]),
            effort: .tooHard, midSetTooHard: true,
            bonus: BonusRecord(offered: .reps(1), accepted: false), completion: .stoppedEarly
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = FixedClock.timeZone
        let builtIDs = Set(ProgressionCatalog.v1.families.flatMap { $0.rungs.map(\.exerciseID) })
        return AdaptiveReplay.snapshot(facts: AdaptiveFacts(evidence: [evidence], calibrations: [calibration]),
                                       builtExerciseIDs: builtIDs, parameters: .standard, calendar: calendar,
                                       asOf: FixedClock.date, appVersion: "test")
    }

    @MainActor
    private final class FakeAdaptiveDebugProvider: AdaptiveDebugProviding {
        private let value: AdaptiveSnapshot

        init(snapshot: AdaptiveSnapshot) {
            value = snapshot
        }

        func adaptiveSnapshot(asOf now: Date) throws -> AdaptiveSnapshot { value }
    }
}
