import XCTest
@testable import PostureAnalysisApp

/// The text report a developer pastes into a chat.
final class WorkoutRecordingReportTests: XCTestCase {
    /// A push-up recording: tracking is lost at 13.27 s and back at 14.4 s, with a marker at 30 s.
    static let sampleLines: [String] = {
        let order = LandmarkType.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        var lines = [
            #"{"k":"header","schema":"fmp.workout-session/1","id":"599FCD69-CD80-4E21-978B-CDEA95DD23FC","startedAt":"2027-01-15T08:00:00.000Z","#
                + #""camera":{"analysisHz":10},"jointOrder":[\#(order)],"confidenceFloor":0.3,"#
                + #""framing":{"minimumConfidence":0.4,"reliableAfter":0.6,"unreliableAfter":0.3},"#
                + #""exercises":{"push_up":{"cameraView":"floor","required":["leftShoulder","rightShoulder"],"anyOfRequired":[],"#
                + #""focus":["leftShoulder","rightShoulder","leftWrist"],"configuration":{"downMaxRatio":0.5,"upMinRatio":0.8}}}}"#,
            #"{"k":"pipe","t":0.36,"control":"exercise","exercise":"push_up","cameraView":"floor","epoch":1}"#,
            #"{"k":"state","t":0.4,"phase":"framing","reps":0}"#,
            #"{"k":"e","t":4.92,"type":"command","command":"start","source":"touch"}"#,
            #"{"k":"state","t":4.92,"phase":"exercising","reps":0}"#,
            #"{"k":"e","t":6.87,"type":"framing","framing":{"ok":true,"g":null}}"#,
            #"{"k":"e","t":13.27,"type":"framing","framing":{"ok":false,"g":"stepBackFloor"}}"#,
            #"{"k":"e","t":13.5,"type":"speak","text":"I can't see you.","muted":false}"#,
            #"{"k":"e","t":14.4,"type":"framing","framing":{"ok":true,"g":null}}"#,
            #"{"k":"e","t":20.0,"type":"startPosition","held":true}"#,
            #"{"k":"marker","t":31,"heardAt":30,"id":"M1","source":"voice","text":"should have counted"}"#,
            #"{"k":"note","id":"N1","markerID":"M1","text":"bottom of the rep"}"#
        ]
        // Frames every 0.1 s from 11.0 to 32.0 s; joints vanish from 13.3 to 14.1 s.
        for step in 110...320 {
            let t = Double(step) / 10
            let ok = !(13.27..<14.4).contains(t) && t >= 6.87
            let joints: String
            if (13.3...14.1).contains(t) {
                joints = Array(repeating: "null", count: LandmarkType.allCases.count).joined(separator: ",")
            } else {
                var cells = Array(repeating: "null", count: LandmarkType.allCases.count)
                cells[LandmarkType.allCases.firstIndex(of: .leftShoulder)!] = "[540.4,882.6,0.35]"
                cells[LandmarkType.allCases.firstIndex(of: .leftWrist)!] = "[512,1244,0.73]"
                joints = cells.joined(separator: ",")
            }
            let low = t == 13.3 ? #","lo":[[7,612,300,0.22]]"# : ""
            lines.append(#"{"k":"f","t":\#(t),"ts":\#(1000 + t),"p":true,"cnt":\#(ok),"j":[\#(joints)]\#(low),"#
                + #""fr":{"ok":\#(ok),"g":null},"rd":{"left":{"signal":0.73,"elbow":126.4,"zone":"middle"}}}"#)
        }
        lines.append(#"{"k":"end","t":57.9,"reason":"workoutEnded","frames":211,"seqGaps":24}"#)
        return lines
    }()

    /// The lines as a closed recording file: a JSON array, one record per line.
    static func fileText(_ lines: [String]) -> String {
        "[\n" + lines.joined(separator: ",\n") + "\n]\n"
    }

    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).json")
        try Self.fileText(Self.sampleLines).write(to: url, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testHeaderNamesTheRecordingItsTuningAndItsFramingRules() {
        let report = make()
        let lines = report.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "FMP workout report · Push-Up · 2027-01-15 08:00 · 0:57 · 211 frames (24 more never reached the coach) · ended: workoutEnded")
        XCTAssertTrue(lines[1].contains("599FCD69-CD80-4E21-978B-CDEA95DD23FC"))
        XCTAssertTrue(report.contains("≥0.4 for 0.6 s"), report)
        XCTAssertTrue(report.contains("Exercise push_up (floor): required LS RS"))
        XCTAssertTrue(report.contains("  tuning: downMaxRatio=0.5 upMinRatio=0.8"))
    }

    func testTimelineListsWhatHappenedButNotStartPositionFlips() {
        let report = make()
        XCTAssertTrue(report.contains("  0:04.9  command start (touch)"))
        XCTAssertTrue(report.contains("  0:04.9  phase exercising"))
        XCTAssertTrue(report.contains("  0:06.9  tracking reliable"))
        XCTAssertTrue(report.contains("  0:13.3  TRACKING LOST (stepBackFloor)"))
        XCTAssertTrue(report.contains("  0:13.5  says “I can't see you.”"))
        XCTAssertTrue(report.contains("  0:14.4  tracking back"))
        XCTAssertTrue(report.contains("  0:30.0  MARKER (voice) “should have counted”"))
        XCTAssertFalse(report.contains("startPosition"))
    }

    func testTrackingLossWindowShowsJointsAtFiveHertz() throws {
        let report = make()
        XCTAssertTrue(report.contains("Tracking lost at 0:13.3 (stepBackFloor), back at 0:14.4, 1.1 s"), report)
        let window = try XCTUnwrap(report.components(separatedBy: "\n\n").first { $0.hasPrefix("Tracking lost") })
        let rows = window.components(separatedBy: "\n").dropFirst(2)
        let times = rows.compactMap { Double($0.trimmingCharacters(in: .whitespaces).prefix { $0 != " " }) }
        XCTAssertEqual(times.first, 12.3, "The window opens 1 s before the loss.")
        XCTAssertEqual(times.last ?? 0, 15.3, accuracy: 0.11, "It closes 1 s after tracking is back.")
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        XCTAssertTrue(gaps.allSatisfy { $0 <= 0.21 }, "\(gaps)")
        XCTAssertTrue(gaps.filter { $0 > 0.15 }.count > 5, "Rows are downsampled to about 5 Hz.")
        XCTAssertTrue(window.contains(" 12.30  ok  on  | .35 540,883 | --          | .73 512,1244"), window)
        XCTAssertTrue(window.contains("LOST off | --          | lo.22"), window)
        XCTAssertTrue(window.contains("L +0.73 126° mid"))
    }

    func testMarkerWindowUsesTheLatestNoteAndLowConfidenceJointsShow() throws {
        let report = make()
        XCTAssertTrue(report.contains("Marker at 0:30.0 (voice): “bottom of the rep”"), report)
        let marker = try XCTUnwrap(report.components(separatedBy: "\n\n").first { $0.hasPrefix("Marker at") })
        XCTAssertTrue(marker.contains(" 22.00 "), "The window opens 8 s before the marker.")
        XCTAssertTrue(marker.contains(" 32.00 "), "It closes 2 s after.")
    }

    func testOverlappingWindowsMerge() {
        var options = WorkoutRecordingReport.Options()
        options.markerBefore = 20
        let report = WorkoutRecordingReport.make(fileURL: url, title: "Push-Up", timeZone: TimeZone(identifier: "UTC")!,
                                                 options: options)
        XCTAssertEqual(report.components(separatedBy: "\n\n").filter { $0.hasPrefix("Tracking lost") || $0.hasPrefix("Marker") }.count, 1)
        XCTAssertTrue(report.contains("Marker at 0:30.0 (voice): “bottom of the rep”; tracking lost at 0:13.3"), report)
    }

    func testRecordingWithoutLossesOrMarkersSaysSo() throws {
        // An unfinished recording: no closing bracket, as after a crash.
        let quiet = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: quiet) }
        try ("[\n" + Self.sampleLines.prefix(5).joined(separator: ",\n")).write(to: quiet, atomically: true, encoding: .utf8)

        let report = WorkoutRecordingReport.make(fileURL: quiet, title: "Push-Up", timeZone: TimeZone(identifier: "UTC")!)

        XCTAssertTrue(report.contains("No tracking losses or markers."))
        XCTAssertTrue(report.contains("· incomplete"))
    }

    func testOlderJSONLinesRecordingsReportTheSame() throws {
        let legacy = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: legacy) }
        try (Self.sampleLines.joined(separator: "\n") + "\n").write(to: legacy, atomically: true, encoding: .utf8)

        XCTAssertEqual(WorkoutRecordingReport.make(fileURL: legacy, title: "Push-Up", timeZone: TimeZone(identifier: "UTC")!),
                       make())
    }

    func testJointNamesAreShortened() {
        XCTAssertEqual(WorkoutRecordingReport.short("leftShoulder"), "LS")
        XCTAssertEqual(WorkoutRecordingReport.short("rightAnkle"), "RA")
        XCTAssertEqual(WorkoutRecordingReport.short("nose"), "Nose")
        XCTAssertEqual(WorkoutRecordingReport.clock(116.44), "1:56.4")
    }

    private func make() -> String {
        WorkoutRecordingReport.make(fileURL: url, title: "Push-Up", timeZone: TimeZone(identifier: "UTC")!)
    }
}
