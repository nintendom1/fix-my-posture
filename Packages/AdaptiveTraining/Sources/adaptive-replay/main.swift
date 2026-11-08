import AdaptiveTraining
import Foundation

private let usage = "usage: adaptive-replay <export.json> [--parameters <parameters.json>]"

private func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("adaptive-replay: \(message)\n".utf8))
    exit(status)
}

private func read(_ path: String, label: String) -> Data {
    do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        fail("could not read \(label) '\(path)': \(error.localizedDescription)", status: 1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let exportPath = arguments.first, !exportPath.isEmpty, !exportPath.hasPrefix("-") else {
    fail(usage, status: 2)
}

var parameterPath: String?
if arguments.count == 1 {
    parameterPath = nil
} else if arguments.count == 3, arguments[1] == "--parameters", !arguments[2].isEmpty,
          !arguments[2].hasPrefix("-") {
    parameterPath = arguments[2]
} else {
    fail(usage, status: 2)
}

let snapshotData = read(exportPath, label: "export")
let snapshot: AdaptiveSnapshot
do {
    snapshot = try AdaptiveExport.decode(snapshotData)
} catch {
    fail("invalid export JSON: \(error.localizedDescription)", status: 1)
}

var parameters: PolicyParameters?
if let parameterPath {
    let parameterData = read(parameterPath, label: "parameters")
    do {
        parameters = try JSONDecoder().decode(PolicyParameters.self, from: parameterData)
    } catch {
        fail("invalid parameters JSON: \(error.localizedDescription)", status: 1)
    }
}

print(ReplayComparison.compare(snapshot, parameters: parameters).report)
