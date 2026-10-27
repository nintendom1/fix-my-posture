import Foundation

/// A problem that makes a catalog unsafe to recommend from; `ProgressionCatalog.problems` lists them.
public enum ProgressionCatalogProblem: Hashable, Sendable, CustomStringConvertible {
    case emptyFamily(MovementFamilyID)
    case floorNotFirst(MovementFamilyID)
    case floorCount(MovementFamilyID, Int)
    case duplicateFamily(MovementFamilyID)
    case duplicateVariant(VariantID)
    case variantOutsideFamily(VariantID, MovementFamilyID)
    case floorNeedsEquipment(MovementFamilyID)

    public var description: String {
        switch self {
        case .emptyFamily(let family): return "\(family) has no rungs"
        case .floorNotFirst(let family): return "\(family)'s floor is not its first rung"
        case .floorCount(let family, let count): return "\(family) has \(count) floors; expected exactly 1"
        case .duplicateFamily(let family): return "\(family) is listed twice"
        case .duplicateVariant(let variant): return "\(variant) is listed twice"
        case .variantOutsideFamily(let variant, let family): return "\(variant) does not start with \(family)."
        case .floorNeedsEquipment(let family): return "\(family)'s floor needs equipment"
        }
    }
}

/// Every movement family's ladder. Recommendation code moves along these ladders; screens never decide
/// what is easier or harder.
public struct ProgressionCatalog: Hashable, Codable, Sendable {
    /// Bumped whenever a ladder changes, so exports say which ladders their variant IDs refer to.
    public let version: String
    public let families: [MovementFamily]

    public init(version: String, families: [MovementFamily]) {
        self.version = version
        self.families = families
    }

    public func family(_ id: MovementFamilyID) -> MovementFamily? {
        families.first { $0.id == id }
    }

    public func family(containing variant: VariantID) -> MovementFamily? {
        families.first { $0.index(of: variant) != nil }
    }

    public func rung(_ variant: VariantID) -> ProgressionRung? {
        family(containing: variant)?.rungs.first { $0.id == variant }
    }

    /// The nearest easier rung that is available, or nil at the floor. Also nil whenever the family's floor isn't
    /// available, because a family without a floor can't be offered at all.
    public func easier(than variant: VariantID, availability: Availability) -> ProgressionRung? {
        guard let (family, index) = offerableFamily(containing: variant, availability: availability) else { return nil }
        return family.rungs[..<index].last(where: availability.isAvailable)
    }

    /// The nearest harder rung that is available, or nil at the top of what the user can do. Also nil whenever the
    /// family's floor isn't available.
    public func harder(than variant: VariantID, availability: Availability) -> ProgressionRung? {
        guard let (family, index) = offerableFamily(containing: variant, availability: availability) else { return nil }
        return family.rungs[(index + 1)...].first(where: availability.isAvailable)
    }

    private func offerableFamily(containing variant: VariantID,
                                 availability: Availability) -> (MovementFamily, Int)? {
        guard let family = family(containing: variant), let index = family.index(of: variant),
              floor(of: family.id, availability: availability) != nil else { return nil }
        return (family, index)
    }

    /// The family's floor when it is available. A family whose floor is missing can't be offered, because
    /// there would be nowhere safe to go when one rep is too hard.
    public func floor(of family: MovementFamilyID, availability: Availability) -> ProgressionRung? {
        guard let floor = self.family(family)?.floor, availability.isAvailable(floor) else { return nil }
        return floor
    }

    /// The easiest prescription a family can give: its floor at the floor's minimum dose.
    public func floorPrescription(of family: MovementFamilyID, availability: Availability) -> RungDose? {
        floor(of: family, availability: availability).map { RungDose(variant: $0.id, dose: $0.minimumDose) }
    }

    /// Families that can be offered now, in catalog order.
    public func offerableFamilies(availability: Availability) -> [MovementFamilyID] {
        families.map(\.id).filter { floor(of: $0, availability: availability) != nil }
    }

    /// Structural problems; an empty list means the catalog is safe to recommend from.
    public var problems: [ProgressionCatalogProblem] {
        var problems: [ProgressionCatalogProblem] = []
        var familyIDs = Set<MovementFamilyID>()
        var variantIDs = Set<VariantID>()
        for family in families {
            if !familyIDs.insert(family.id).inserted { problems.append(.duplicateFamily(family.id)) }
            guard let first = family.rungs.first else {
                problems.append(.emptyFamily(family.id))
                continue
            }
            let floors = family.rungs.filter(\.isFloor).count
            if floors != 1 { problems.append(.floorCount(family.id, floors)) }
            if floors >= 1, !first.isFloor { problems.append(.floorNotFirst(family.id)) }
            if first.isFloor, !first.requiredEquipment.isEmpty { problems.append(.floorNeedsEquipment(family.id)) }
            for rung in family.rungs {
                if !variantIDs.insert(rung.id).inserted { problems.append(.duplicateVariant(rung.id)) }
                if !rung.id.rawValue.hasPrefix(family.id.rawValue + ".") {
                    problems.append(.variantOutsideFamily(rung.id, family.id))
                }
            }
        }
        return problems
    }
}
