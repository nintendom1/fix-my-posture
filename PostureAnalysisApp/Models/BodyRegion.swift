import Foundation

/// Key body regions evaluated independently for posture reference generation.
public enum BodyRegion: String, Codable, Hashable, CaseIterable {
    case head = "Head"
    case torso = "Torso / Pelvis"
    case legs = "Legs"
    case arms = "Arms"
}
