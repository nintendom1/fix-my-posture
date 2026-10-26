import Foundation

/// What a session recording needs from one exercise: the configuration its analyzer was built with, and a way
/// to rebuild the exercise from a recorded configuration so replay runs exactly what the phone ran.
struct ExerciseDiagnostics {
    /// The configuration as JSON with sorted keys.
    let configurationJSON: String
    /// Rebuilds the exercise from recorded configuration JSON. Keys the recording lacks keep this
    /// configuration's values, and keys this build no longer has are ignored.
    let rebuild: (_ configurationJSON: Data) throws -> ExerciseDefinition

    init<Configuration: Codable>(_ configuration: Configuration,
                                 definition: @escaping (Configuration) -> ExerciseDefinition) {
        let base = (try? Self.encoder.encode(configuration)) ?? Data("{}".utf8)
        configurationJSON = String(decoding: base, as: UTF8.self)
        rebuild = { recorded in
            let merged = try Self.merge(recorded, over: base)
            return definition(try JSONDecoder().decode(Configuration.self, from: merged))
        }
    }

    /// Sorted keys, so the same configuration always encodes to the same text.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Encodes any of the shared configurations (framing, joints past the edge, cue scheduling) the same way.
    static func json<Value: Encodable>(_ value: Value) -> String {
        (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// Lays the recorded values over the current configuration's encoding, key by key.
    static func merge(_ recorded: Data, over base: Data) throws -> Data {
        guard var current = try JSONSerialization.jsonObject(with: base) as? [String: Any],
              let overlay = try JSONSerialization.jsonObject(with: recorded) as? [String: Any] else { return base }
        for (key, value) in overlay where current[key] != nil {
            current[key] = value
        }
        return try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys])
    }
}
