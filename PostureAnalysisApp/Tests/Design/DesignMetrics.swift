import Foundation
import CoreGraphics

enum DesignAnchorKind: String, Codable {
    case box
    case text
}

struct DesignAnchorMetric: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let kind: DesignAnchorKind
}

struct DesignViewport: Codable {
    let width: Int
    let height: Int
    let scale: Int
}

struct DesignFrameMetric: Codable {
    let label: String
    let attrs: [String: JSONValue]
    let anchors: [String: DesignAnchorMetric]
    let icons: [String]
    let colors: [String: String]
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct DesignMetricsDocument: Codable {
    let version: Int
    let renderer: String
    let viewport: DesignViewport
    let frames: [String: DesignFrameMetric]
    let allIcons: [String]
}

enum DesignMetrics {
    static func load(filePath: String = #filePath) throws -> DesignMetricsDocument {
        let source = URL(fileURLWithPath: filePath)
        var directory = source.deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("Design/Metrics/design-metrics.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder().decode(DesignMetricsDocument.self, from: Data(contentsOf: candidate))
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Design/Metrics/design-metrics.json"])
    }

    static func tolerance(for kind: DesignAnchorKind) -> CGFloat {
        switch kind {
        case .box: return 1
        case .text: return 2
        }
    }
}
