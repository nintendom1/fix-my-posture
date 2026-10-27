import Foundation

public enum PrescriptionKind: String, Codable, CaseIterable, Sendable {
    case todaySession
    case calibrationProbe
}

public enum PrescriptionItemRole: String, Codable, CaseIterable, Sendable {
    /// The day's required item.
    case main
    /// An optional one-rep sample of the next harder rung; declining it is neutral.
    case harderSample
    /// The easier version the user took mid-item.
    case easierSwap
}

public struct PrescriptionItem: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let family: MovementFamilyID
    public let target: RungDose
    public let role: PrescriptionItemRole
    /// Whether an Easy rating may offer a bonus.
    public let offersBonus: Bool

    public init(id: UUID, family: MovementFamilyID, target: RungDose, role: PrescriptionItemRole = .main,
                offersBonus: Bool = true) {
        self.id = id
        self.family = family
        self.target = target
        self.role = role
        self.offersBonus = offersBonus
    }

    public var isOptional: Bool { role == .harderSample }
}

/// What the app asked for, saved when the user starts it so evidence can point at the exact item.
public struct Prescription: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let issuedAt: Date
    public let kind: PrescriptionKind
    public let policyVersion: PolicyVersion
    public let catalogVersion: String
    public let items: [PrescriptionItem]
    /// The readable rationale shown when the prescription was issued.
    public let rationale: String

    public init(id: UUID, issuedAt: Date, kind: PrescriptionKind, policyVersion: PolicyVersion,
                catalogVersion: String, items: [PrescriptionItem], rationale: String) {
        self.id = id
        self.issuedAt = issuedAt
        self.kind = kind
        self.policyVersion = policyVersion
        self.catalogVersion = catalogVersion
        self.items = items
        self.rationale = rationale
    }
}
