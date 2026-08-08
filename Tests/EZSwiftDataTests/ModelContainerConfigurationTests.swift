import SwiftData
import Testing
@testable import EZSwiftData

private enum EmptyTestMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = []
    static let stages: [MigrationStage] = []
}

@Suite("ModelContainerFactory configurations", .serialized)
@MainActor
struct ModelContainerConfigurationTests {
    @Test("Existing variadic API creates a container")
    func existingVariadicAPI() throws {
        let container = try ModelContainerFactory.create(
            isStoredInMemoryOnly: true,
            TestPet.self,
            TestOwner.self
        )

        #expect(container.mainContext.container === container)
    }

    @Test("Default ModelConfiguration uses persistent storage")
    func defaultPersistentConfiguration() throws {
        var isPersistent = false
        _ = try ModelContainerFactory.create(for: [TestPet.self]) { schema in
            let configuration = ModelConfiguration(
                "EZSwiftDataConfigurationTests",
                schema: schema,
                cloudKitDatabase: .none
            )
            isPersistent = !configuration.isStoredInMemoryOnly
            return configuration
        }

        #expect(isPersistent)
    }

    @Test("In-memory convenience creates a usable container")
    func inMemoryConvenience() throws {
        let container = try ModelContainerFactory.create(
            for: [TestPet.self],
            isStoredInMemoryOnly: true
        )

        container.mainContext.insert(TestPet(name: "Memory"))
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<TestPet>()).count == 1)
    }

    @Test("Custom configuration receives the resolved schema")
    func customConfigurationReceivesSchema() throws {
        var receivedVersion: Schema.Version?
        let container = try ModelContainerFactory.create(
            for: [TestPet.self, TestOwner.self]
        ) { schema in
            receivedVersion = schema.version
            return ModelConfiguration(
                "Custom",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }

        #expect(receivedVersion == container.schema.version)
    }

    @Test("SwiftData CloudKit can be explicitly disabled")
    func cloudKitCanBeDisabled() throws {
        var cloudKitIsDisabled = false
        _ = try ModelContainerFactory.create(for: [TestPet.self]) { schema in
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            if case .none = configuration.cloudKitDatabase {
                cloudKitIsDisabled = true
            }
            return configuration
        }

        #expect(cloudKitIsDisabled)
    }

    @Test("Versioned schema supports custom configuration")
    func versionedSchemaCustomConfiguration() throws {
        var receivedVersion: Schema.Version?
        let container = try ModelContainerFactory.create(
            for: TestSchemaV2.self
        ) { schema in
            receivedVersion = schema.version
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        #expect(receivedVersion == TestSchemaV2.versionIdentifier)
        #expect(container.schema.version == TestSchemaV2.versionIdentifier)
    }

    @Test("Migration plan supports custom configuration")
    func migrationPlanCustomConfiguration() throws {
        let explicitContainer = try ModelContainerFactory.create(
            for: TestSchemaV2.self,
            migrationPlan: TestMigrationPlan.self
        ) { schema in
            ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        var receivedVersion: Schema.Version?
        let container = try ModelContainerFactory.create(
            migrationPlan: TestMigrationPlan.self
        ) { schema in
            receivedVersion = schema.version
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        #expect(receivedVersion == TestSchemaV2.versionIdentifier)
        #expect(explicitContainer.migrationPlan == TestMigrationPlan.self)
        #expect(container.migrationPlan == TestMigrationPlan.self)
    }

    @Test("Synchronous seeding supports custom configuration")
    func synchronousSeedCustomConfiguration() throws {
        let container = try ModelContainerFactory.createSeeded(
            for: [TestPet.self],
            configuration: inMemoryConfiguration
        ) { context in
            context.insert(TestPet(name: "Synchronous"))
        }

        #expect(!container.mainContext.hasChanges)
        #expect(try container.mainContext.fetch(FetchDescriptor<TestPet>()).count == 1)
    }

    @Test("Asynchronous seeding supports custom configuration")
    func asynchronousSeedCustomConfiguration() async throws {
        let container = try await ModelContainerFactory.createSeeded(
            for: [TestPet.self],
            configuration: inMemoryConfiguration
        ) { context in
            context.insert(TestPet(name: "Asynchronous"))
        }

        #expect(!container.mainContext.hasChanges)
        #expect(try container.mainContext.fetch(FetchDescriptor<TestPet>()).count == 1)
    }

    @Test("An empty model list still fails")
    func emptyModelList() {
        #expect(throws: ModelContainerFactory.Error.emptyModelList) {
            try ModelContainerFactory.create(for: []) { schema in
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        }
    }

    @Test("An empty migration plan still fails")
    func emptyMigrationPlan() {
        #expect(throws: ModelContainerFactory.Error.emptyMigrationPlan) {
            try ModelContainerFactory.create(
                migrationPlan: EmptyTestMigrationPlan.self
            ) { schema in
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        }
    }

    private func inMemoryConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }
}
