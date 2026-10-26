import XCTest
@testable import PostureAnalysisApp

/// The compact JSON writer behind session recordings.
final class DiagnosticJSONTests: XCTestCase {
    func testNumbersReadBackExactly() {
        let values: [Double] = [540.0926208496094, 0.1 + 0.2, 1e-7, -3.5, 0, 1920, 123456.789, 0.9345703125, 1e20]
        for value in values {
            let text = DiagnosticJSON.double(value).serialized
            XCTAssertEqual(Double(text), value, "\(value) was written as \(text)")
        }
        XCTAssertEqual(DiagnosticJSON.double(540).serialized, "540")
        XCTAssertEqual(DiagnosticJSON.int(-12).serialized, "-12")
    }

    func testNonFiniteNumbersAreWrittenAsNull() {
        XCTAssertEqual(DiagnosticJSON.double(.nan).serialized, "null")
        XCTAssertEqual(DiagnosticJSON.double(.infinity).serialized, "null")
        XCTAssertEqual(DiagnosticJSON.rounded(.nan).serialized, "null")
    }

    func testRoundedKeepsTheRequestedPlaces() {
        XCTAssertEqual(DiagnosticJSON.rounded(0.123456).serialized, "0.1235")
        XCTAssertEqual(DiagnosticJSON.rounded(138.44449, places: 2).serialized, "138.44")
        XCTAssertEqual(DiagnosticJSON.rounded(2.0).serialized, "2")
    }

    func testObjectsKeepTheirKeyOrderAndLeaveOutNilMembers() {
        let missing: DiagnosticJSON? = nil
        let json = DiagnosticJSON.object(("k", "f"), ("t", 1.5), ("gone", missing), ("ok", true), ("a", [1, 2]))
        XCTAssertEqual(json.serialized, #"{"k":"f","t":1.5,"ok":true,"a":[1,2]}"#)
    }

    func testStringsAreEscapedSoTheyParseBack() throws {
        let text = "Say \u{201C}mark that\u{201D} \"now\" \\ ok\nnext\ttab \u{01} 💪"
        let line = DiagnosticJSON.object(("text", .string(text))).serialized
        XCTAssertFalse(line.contains("\n"), "A line must stay on one line.")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])
        XCTAssertEqual(object["text"], text)
    }

    func testRawFragmentsAreWrittenAsIs() {
        let json = DiagnosticJSON.object(("configuration", .raw(#"{"a":1}"#)))
        XCTAssertEqual(json.serialized, #"{"configuration":{"a":1}}"#)
    }
}
