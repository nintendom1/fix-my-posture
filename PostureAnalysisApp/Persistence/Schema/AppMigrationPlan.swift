import SwiftData

/// The migration plan is versioned even while V1 is the only released schema.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    static var stages: [MigrationStage] = []
}
