import Foundation
import Testing

@testable import EZSwiftDataCloudKit

private struct Project: CloudShareable, Equatable {
  let id: UUID
  var name: String
}

@Suite("Cloud model infrastructure")
struct CloudModelTests {
  @Test func validatesShareURLs() throws {
    let validURL = try #require(URL(string: "https://www.icloud.com/share/example"))
    let invalidURL = try #require(URL(string: "https://example.com/share"))
    let valid = try CloudShareURL(validURL)
    #expect(valid.url.host == "www.icloud.com")
    #expect(throws: CloudKitSharingError.invalidShareURL) {
      try CloudShareURL(invalidURL)
    }
  }

  @Test func inMemoryStoreRoundTripsModels() async throws {
    let project = Project(id: UUID(), name: "Package")
    let store = InMemoryCloudModelStore<Project>()
    await store.save(project)
    #expect(await store.model(for: project.id) == project)
    await store.removeAllLocalModels()
    #expect(await store.model(for: project.id) == nil)
  }

  @Test func migrationsFollowDeterministicPath() throws {
    let first = CloudMigration(from: 1, to: 2) { $0 + Data("2".utf8) }
    let second = CloudMigration(from: 2, to: 3) { $0 + Data("3".utf8) }
    let registry = try CloudMigrationRegistry([first, second])
    #expect(try registry.migrate(Data("1".utf8), from: 1, to: 3) == Data("123".utf8))
  }

  @Test func retryEventuallySucceeds() async throws {
    let attempts = AttemptCounter()
    let queue = CloudOperationQueue()
    let result: String = try await queue.run(
      retry: .init(maximumAttempts: 3, initialDelay: .zero, maximumDelay: .zero)
    ) {
      let attempt = await attempts.next()
      if attempt < 3 { throw RetryError.transient }
      return "done"
    }
    #expect(result == "done")
  }
}

private actor AttemptCounter {
  private var value = 0
  func next() -> Int {
    value += 1
    return value
  }
}
private enum RetryError: Error { case transient }
