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
        return try create(
            for: models,
            configuration: { schema in
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly
                )
            }
        )
    }

    /// Creates a `ModelContainer` using a native SwiftData configuration.
    ///
    /// The builder receives the exact schema passed to `ModelContainer`, which
    /// keeps custom store settings aligned with the requested model types.
    ///
    /// - Parameters:
    ///   - models: The persistent model types included in the schema.
    ///   - configuration: A builder returning the native `ModelConfiguration`.
    @MainActor
    public static func create(
        for models: [any PersistentModel.Type],
        configuration: (Schema) -> ModelConfiguration
    ) throws -> ModelContainer {
        guard !models.isEmpty else {
            throw Error.emptyModelList
        }

        let schema = Schema(models)
        return try create(
            for: schema,
            migrationPlan: nil,
            configuration: configuration(schema)
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
        try create(
            for: versionedSchema,
            migrationPlan: migrationPlan,
            configuration: { schema in
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly
                )
            }
        )
    }

    /// Creates a `ModelContainer` for a versioned schema using a native
    /// SwiftData configuration.
    ///
    /// - Parameters:
    ///   - versionedSchema: The current version of the schema to load.
    ///   - migrationPlan: An optional plan for migrating older stores.
    ///   - configuration: A builder that receives the resolved versioned schema.
    @MainActor
    public static func create<SchemaVersion: VersionedSchema>(
        for versionedSchema: SchemaVersion.Type,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        configuration: (Schema) -> ModelConfiguration
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versionedSchema)
        return try create(
            for: schema,
            migrationPlan: migrationPlan,
            configuration: configuration(schema)
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
        return try create(
            migrationPlan: migrationPlan,
            configuration: { schema in
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly
                )
            }
        )
    }

    /// Creates a `ModelContainer` using the latest schema in a migration plan
    /// and a native SwiftData configuration.
    ///
    /// - Parameters:
    ///   - migrationPlan: The migration plan describing the schema evolution.
    ///   - configuration: A builder that receives the plan's latest schema.
    @MainActor
    public static func create<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type,
        configuration: (Schema) -> ModelConfiguration
    ) throws -> ModelContainer {
        guard let currentSchema = migrationPlan.schemas.last else {
            throw Error.emptyMigrationPlan
        }

        let schema = Schema(versionedSchema: currentSchema)
        return try create(
            for: schema,
            migrationPlan: migrationPlan,
            configuration: configuration(schema)
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
        let context = container.mainContext
        try seed(context)
        try context.save()
        return container
    }

    /// Creates a custom-configured `ModelContainer`, then immediately seeds it.
    ///
    /// - Parameters:
    ///   - models: The persistent model types included in the schema.
    ///   - configuration: A builder returning the native `ModelConfiguration`.
    ///   - seed: The synchronous seeding closure, executed on the `MainActor`.
    @MainActor
    public static func createSeeded(
        for models: [any PersistentModel.Type],
        configuration: (Schema) -> ModelConfiguration,
        seed: @MainActor (ModelContext) throws -> Void
    ) throws -> ModelContainer {
        let container = try create(for: models, configuration: configuration)
        let context = container.mainContext
        try seed(context)
        try context.save()
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

    /// Creates a `ModelContainer`, then asynchronously seeds it.
    ///
    /// This is useful when seed data requires async work while still
    /// ensuring model context mutations stay on the `MainActor`.
    @MainActor
    public static func createSeeded(
        for models: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false,
        seed: @MainActor (ModelContext) async throws -> Void
    ) async throws -> ModelContainer {
        let container = try create(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly)
        let context = container.mainContext
        try await seed(context)
        try context.save()
        return container
    }

    /// Creates a custom-configured `ModelContainer`, then asynchronously seeds it.
    ///
    /// - Parameters:
    ///   - models: The persistent model types included in the schema.
    ///   - configuration: A builder returning the native `ModelConfiguration`.
    ///   - seed: The asynchronous seeding closure, executed on the `MainActor`.
    @MainActor
    public static func createSeeded(
        for models: [any PersistentModel.Type],
        configuration: (Schema) -> ModelConfiguration,
        seed: @MainActor (ModelContext) async throws -> Void
    ) async throws -> ModelContainer {
        let container = try create(for: models, configuration: configuration)
        let context = container.mainContext
        try await seed(context)
        try context.save()
        return container
    }

    /// Variadic convenience overload for async `createSeeded`.
    @MainActor
    public static func createSeeded(
        isStoredInMemoryOnly: Bool = false,
        seed: @MainActor (ModelContext) async throws -> Void,
        _ models: any PersistentModel.Type...
    ) async throws -> ModelContainer {
        try await createSeeded(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly, seed: seed)
    }
}
