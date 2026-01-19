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

    /// Creates a `ModelContainer` for the provided model types.
    ///
    /// - Parameters:
    ///   - models: The list of persistent models (e.g., `[Pet.self]`).
    ///   - isStoredInMemoryOnly: Set to `true` for unit tests or previews.
    @MainActor
    public static func create(
        for models: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false
    ) -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not create model container: \(error.localizedDescription)")
        }
    }

    /// Variadic convenience overload.
    @MainActor
    public static func create(
        isStoredInMemoryOnly: Bool = false,
        _ models: any PersistentModel.Type...
    ) -> ModelContainer {
        create(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly)
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
        seed: @MainActor (ModelContext) -> Void
    ) -> ModelContainer {
        let container = create(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly)
        seed(container.mainContext)
        return container
    }

    /// Variadic convenience overload for `createSeeded`.
    @MainActor
    public static func createSeeded(
        isStoredInMemoryOnly: Bool = false,
        seed: @MainActor (ModelContext) -> Void,
        _ models: any PersistentModel.Type...
    ) -> ModelContainer {
        createSeeded(for: models, isStoredInMemoryOnly: isStoredInMemoryOnly, seed: seed)
    }
}
