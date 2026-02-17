//
//  SwiftDataPreviewerTests.swift
//  SwiftDataPreviewerTests
//
//  These tests are designed to exercise the public surface of the package.
//  They focus on success paths and helper APIs that are safe to run in XCTest.
//
//  Note: Testing fatalError branches generally requires a small test hook.
//  If you decide to add an injectable error handler to ModelContainerFactory,
//  you can extend these tests to assert the failure path too.
//

import XCTest
import SwiftUI
import SwiftData
@testable import EZSwiftData

// MARK: - Test Models

@Model
final class TestPet {
    var name: String
    
    init(name: String = "") {
        self.name = name
    }
    
    @MainActor
    static let samples: [TestPet] = [
        TestPet(name: "A"),
        TestPet(name: "B"),
        TestPet(name: "C")
    ]
}

@Model
final class TestOwner {
    var name: String
    
    init(name: String = "") {
        self.name = name
    }
    
    @MainActor
    static let samples: [TestOwner] = [
        TestOwner(name: "O1"),
        TestOwner(name: "O2")
    ]
}

// MARK: - Preview Config for Tests

enum TestPreviewConfig: SwiftDataPreviewContextConfig {
    static let models: [any PersistentModel.Type] = [
        TestPet.self,
        TestOwner.self
    ]
    
    @MainActor
    static func seed(_ context: ModelContext) {
        context.insert(TestPet.samples)
        context.insert(TestOwner.samples)
    }
}

// MARK: - Dependencies Modifier for Tests

struct TestPreviewDependencies: ViewModifier {
    let context: ModelContext
    
    func body(content: Content) -> some View {
        // Keep this minimal; we just want to validate it can be constructed.
        let _ = context
        return content
    }
}

// MARK: - Tests

final class ModelContainerFactoryTests: XCTestCase {
    
    @MainActor
    func testCreateSharedContainerWithVariadicModels() throws {
        let container = try ModelContainerFactory.create(
            TestPet.self,
            TestOwner.self
        )
        
        // Assert the container provides a valid main context.
        XCTAssertNotNil(container.mainContext)
    }
    
    @MainActor
    func testCreateInMemoryContainerViaCreateFlag() throws {
        let container = try ModelContainerFactory.create(
            for: [TestPet.self, TestOwner.self],
            isStoredInMemoryOnly: true
        )
        
        XCTAssertNotNil(container.mainContext)
    }
}

final class ModelContextInsertHelpersTests: XCTestCase {
    
    @MainActor
    func testInsertSequenceHelper() throws {
        let container = try ModelContainerFactory.createTestInMemory(
            models: [TestPet.self]
        )
        let context = container.mainContext
        
        context.insert(TestPet.samples)
        
        // Fetch to verify inserts.
        let descriptor = FetchDescriptor<TestPet>()
        let results = try context.fetch(descriptor)
        let expectedCount = TestPet.samples.count
        XCTAssertEqual(results.count, expectedCount)
    }
    
    @MainActor
    func testInsertVariadicHelper() throws {
        let container = try ModelContainerFactory.createTestInMemory(
            models: [TestPet.self]
        )
        let context = container.mainContext
        
        let p1 = TestPet(name: "X")
        let p2 = TestPet(name: "Y")
        context.insert(p1, p2)
        
        let descriptor = FetchDescriptor<TestPet>()
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 2)
    }
}

final class PreviewTraitConvenienceTests: XCTestCase {
    
    @MainActor func testSeededTraitBuilds() {
        // This is a lightweight compile-time + runtime sanity check.
        let trait = PreviewTrait.seeded(TestPreviewConfig.self)
        XCTAssertNotNil(trait)
    }
    
    @MainActor func testDevTraitBuilds() {
        let trait = PreviewTrait.dev(TestPreviewConfig.self) { ctx in
            TestPreviewDependencies(context: ctx)
        }
        XCTAssertNotNil(trait)
    }
}

final class DataPreviewerTests: XCTestCase {
    
    func testDataPreviewerStaticContextCreation() async throws {
        // Ensure the PreviewModifier's shared context can be produced.
        let container = try await DataPreviewer<TestPreviewConfig, EmptyModifier>.makeSharedContext()

        // Access ModelContext and perform fetches on the main actor to avoid crossing isolation.
        let (petsCount, ownersCount): (Int, Int) = await MainActor.run {
            let context = container.mainContext
            let pets = try? context.fetch(FetchDescriptor<TestPet>())
            let owners = try? context.fetch(FetchDescriptor<TestOwner>())
            return (pets?.count ?? 0, owners?.count ?? 0)
        }

        // Read sample counts on the main actor as well to avoid nonisolated autoclosure capture.
        let (expectedPets, expectedOwners): (Int, Int) = await MainActor.run {
            (TestPet.samples.count, TestOwner.samples.count)
        }

        XCTAssertEqual(petsCount, expectedPets)
        XCTAssertEqual(ownersCount, expectedOwners)
    }
}

// MARK: - Test-only helper to avoid duplicating in-memory setup

private extension ModelContainerFactory {
    @MainActor
    static func createTestInMemory(
        models: [any PersistentModel.Type]
    ) throws -> ModelContainer {
        // We purposely call the same public API to keep behavior aligned.
        // This is kept in tests to avoid encouraging a public in-memory API
        // in production if you don't want it.
        return try create(for: models, isStoredInMemoryOnly: true)
    }
}

