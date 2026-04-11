//
//  ModelContainerFactory.swift
//  EZSwiftData
//
//  Created by Gerard Gomez on 12/6/25.
//


import SwiftData

// MARK: - Production Factory

/// A small factory for creating SwiftData containers for production,
/// previews, and tests.
nonisolated public struct ModelContainerFactory {
    public enum Error: Swift.Error, Equatable {
        case emptyModelList
        case emptyMigrationPlan
        case containerCreationFailed(String)
    }

    /// Creates a `ModelContainer` for the provided model types.
    ///
    /// - Parameters:
    ///   - models: The list of persistent models (e.g., `[Pet.self]`).
    ///   - isStoredInMemoryOnly: Set to `true` for unit tests or previews.
    @MainActor
    public static func create(
        for models: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        guard !models.isEmpty else {
            throw Error.emptyModelList
        }

        let schema = Schema(models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        return try create(
            for: schema,
            migrationPlan: nil,
            configuration: configuration
        )
    }

    /// Creates a `ModelContainer` for the provided versioned schema.
    ///
    /// - Parameters:
    ///   - versionedSchema: The current version of the schema to load.
    ///   - migrationPlan: An optional migration plan describing how to move
    ///     older stores to `versionedSchema`.
    ///   - isStoredInMemoryOnly: Set to `true` for unit tests or previews.
    @MainActor
    public static func create<SchemaVersion: VersionedSchema>(
        for versionedSchema: SchemaVersion.Type,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versionedSchema)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        return try create(
            for: schema,
            migrationPlan: migrationPlan,
            configuration: configuration
        )
    }

    /// Creates a `ModelContainer` using the latest schema defined by a migration plan.
    ///
    /// - Parameters:
    ///   - migrationPlan: The migration plan describing the schema evolution.
    ///   - isStoredInMemoryOnly: Set to `true` for unit tests or previews.
    @MainActor
    public static func create<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        guard let currentSchema = migrationPlan.schemas.last else {
            throw Error.emptyMigrationPlan
        }

        return try create(
            for: currentSchema,
            migrationPlan: migrationPlan,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
    }

    @MainActor
    private static func create(
        for schema: Schema,
        migrationPlan: (any SchemaMigrationPlan.Type)?,
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: configuration
            )
        } catch {
            throw Error.containerCreationFailed(error.localizedDescription)
        }
    }

    /// Variadic convenience overload.
    @MainActor
    public static func create(
        isStoredInMemoryOnly: Bool = false,
        _ models: any PersistentModel.Type...
    ) throws -> ModelContainer {
        try create(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly)
    }

    /// Creates a `ModelContainer`, then immediately seeds it.
    ///
    /// - Parameters:
    ///   - models: The list of persistent models (e.g., `[Pet.self]`).
    ///   - isStoredInMemoryOnly: Set to `true` for unit tests or previews.
    ///   - seed: The seeding closure, executed on the `MainActor`.
    @MainActor
    public static func createSeeded(
        for models: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false,
        seed: @MainActor (ModelContext) throws -> Void
    ) throws -> ModelContainer {
        let container = try create(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly)
        try seed(container.mainContext)
        return container
    }

    /// Variadic convenience overload for `createSeeded`.
    @MainActor
    public static func createSeeded(
        isStoredInMemoryOnly: Bool = false,
        seed: @MainActor (ModelContext) throws -> Void,
        _ models: any PersistentModel.Type...
    ) throws -> ModelContainer {
        try createSeeded(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly, seed: seed)
    }
}
