import Foundation

public protocol CloudModelStore<Model>: Sendable where Model: CloudShareable {
  associatedtype Model
  func model(for id: Model.ID) async throws -> Model?
  func save(_ model: Model) async throws
  func remove(id: Model.ID) async throws
  func removeAllLocalModels() async throws
}

public actor InMemoryCloudModelStore<Model: CloudShareable>: CloudModelStore
where Model.ID: Hashable {
  private var models: [Model.ID: Model]
  public init(_ models: [Model] = []) {
    self.models = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
  }
  public func model(for id: Model.ID) -> Model? { models[id] }
  public func save(_ model: Model) { models[model.id] = model }
  public func remove(id: Model.ID) { models[id] = nil }
  public func removeAllLocalModels() { models.removeAll() }
  public var values: [Model] { Array(models.values) }
}

public struct CloudMigration: Sendable {
  public let fromVersion: Int
  public let toVersion: Int
  private let transform: @Sendable (Data) throws -> Data

  public init(
    from fromVersion: Int,
    to toVersion: Int,
    transform: @escaping @Sendable (Data) throws -> Data
  ) {
    precondition(toVersion > fromVersion, "A migration must advance the model version")
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.transform = transform
  }

  public func migrate(_ payload: Data) throws -> Data { try transform(payload) }
}

public struct CloudMigrationRegistry: Sendable {
  private let migrations: [Int: CloudMigration]
  public init(_ migrations: [CloudMigration]) throws {
    var indexed: [Int: CloudMigration] = [:]
    for migration in migrations {
      guard indexed.updateValue(migration, forKey: migration.fromVersion) == nil else {
        throw CloudKitSharingError.unsupportedOperation(
          "More than one migration starts at version \(migration.fromVersion)")
      }
    }
    self.migrations = indexed
  }

  public func migrate(_ payload: Data, from source: Int, to target: Int) throws -> Data {
    var data = payload
    var version = source
    while version < target {
      guard let migration = migrations[version], migration.toVersion <= target else {
        throw CloudKitSharingError.unsupportedOperation(
          "No deterministic migration path from version \(version) to \(target)")
      }
      data = try migration.migrate(data)
      version = migration.toVersion
    }
    return data
  }
}

public struct CloudRetryPolicy: Hashable, Sendable {
  public var maximumAttempts: Int
  public var initialDelay: Duration
  public var maximumDelay: Duration
  public init(
    maximumAttempts: Int = 4,
    initialDelay: Duration = .milliseconds(500),
    maximumDelay: Duration = .seconds(30)
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
  }
  public static let automatic = Self()
}

public actor CloudOperationQueue {
  public init() {}
  public func run<Value: Sendable>(
    retry policy: CloudRetryPolicy = .automatic,
    operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    var attempt = 1
    var delay = policy.initialDelay
    while true {
      try Task.checkCancellation()
      do { return try await operation() } catch where attempt < policy.maximumAttempts {
        try await Task.sleep(for: delay)
        attempt += 1
        delay = min(delay * 2, policy.maximumDelay)
      } catch { throw error }
    }
  }
}

public enum CloudConflictPolicy: Sendable {
  case serverWins
  case localWins
  case lastWriterWins
}

public enum CloudDiagnosticEvent: Hashable, Sendable {
  case zoneCreated
  case recordSaved
  case shareCreated
  case shareAccepted
  case participantChanged
  case syncConflict
  case operationRetried(attempt: Int)
}

public actor CloudDiagnostics {
  public typealias Handler = @Sendable (CloudDiagnosticEvent) -> Void
  private let handler: Handler?
  public init(handler: Handler? = nil) { self.handler = handler }
  public func emit(_ event: CloudDiagnosticEvent) { handler?(event) }
  public static let disabled = CloudDiagnostics()
}

/// A deterministic local backend for unit tests; it never contacts iCloud.
public actor TestingCloud<Model: CloudShareable> where Model.ID: Hashable {
  private let store: InMemoryCloudModelStore<Model>
  public init(models: [Model] = []) { store = .init(models) }
  public func save(_ model: Model) async { await store.save(model) }
  public func model(for id: Model.ID) async -> Model? { await store.model(for: id) }
  public func resetLocalState() async { await store.removeAllLocalModels() }
}
