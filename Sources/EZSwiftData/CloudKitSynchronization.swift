#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

/// A remote record change represented without transferring a mutable `CKRecord`.
public struct CloudKitRecordChange: Hashable, Sendable {
    public let identity: CloudKitRecordIdentity
    public let recordType: String
    public let changedKeys: Set<String>?
    public init(identity: CloudKitRecordIdentity, recordType: String, changedKeys: Set<String>? = nil) { self.identity = identity; self.recordType = recordType; self.changedKeys = changedKeys }
}

/// A remote deletion (tombstone). Applications decide whether it deletes a local cache entry.
public struct CloudKitRecordDeletion: Hashable, Sendable {
    public let identity: CloudKitRecordIdentity
    public let recordType: String?
    public init(identity: CloudKitRecordIdentity, recordType: String? = nil) { self.identity = identity; self.recordType = recordType }
}

/// Events emitted by the synchronization coordinator.
public enum CloudKitSyncEvent: Sendable {
    case accountChanged
    case synchronizationStarted(database: CloudKitSharingDatabase)
    case recordsChanged([CloudKitRecordChange])
    case recordsDeleted([CloudKitRecordDeletion])
    case conflict(client: CloudKitRecordSnapshot, server: CloudKitRecordSnapshot)
    case collaborationAdded(CloudKitCollaborationSummary)
    case collaborationRemoved(zoneName: String, ownerName: String)
    case synchronizationFinished(database: CloudKitSharingDatabase)
    case failed(CloudKitSharingFailure)
}

/// The result of classifying an incoming push payload.
public enum CloudKitNotificationResult: Sendable { case ignored, synchronizationScheduled(database: CloudKitSharingDatabase?) }

/// Conflict behavior applied to `serverRecordChanged` snapshots.
public enum CloudKitConflictPolicy: Sendable {
    case serverWins, clientWins, newestModificationDateWins
    case custom(@Sendable (CloudKitRecordSnapshot, CloudKitRecordSnapshot) async throws -> CloudKitRecordSnapshot)
    public func resolve(client: CloudKitRecordSnapshot, server: CloudKitRecordSnapshot) async throws -> CloudKitRecordSnapshot {
        switch self {
        case .serverWins: server
        case .clientWins: client
        case .newestModificationDateWins: (client.modificationDate ?? .distantPast) > (server.modificationDate ?? .distantPast) ? client : server
        case let .custom(resolver): try await resolver(client, server)
        }
    }
}

/// Durable synchronization state. Tokens are opaque archived CloudKit values.
public struct CloudKitSyncState: Codable, Sendable {
    public var privateDatabaseToken: Data?
    public var sharedDatabaseToken: Data?
    public var zoneTokens: [String: Data]
    public var knownSharedZoneKeys: Set<String>
    public init(privateDatabaseToken: Data? = nil, sharedDatabaseToken: Data? = nil, zoneTokens: [String: Data] = [:], knownSharedZoneKeys: Set<String> = []) {
        self.privateDatabaseToken = privateDatabaseToken; self.sharedDatabaseToken = sharedDatabaseToken
        self.zoneTokens = zoneTokens; self.knownSharedZoneKeys = knownSharedZoneKeys
    }
}

/// Storage used for synchronization state. Implementations must make writes durable before returning.
public protocol CloudKitSyncStateStore: Sendable {
    func load(containerIdentifier: String) async throws -> CloudKitSyncState?
    func save(_ state: CloudKitSyncState, containerIdentifier: String) async throws
    func remove(containerIdentifier: String) async throws
}

/// Atomic Application Support storage for CloudKit synchronization state.
public actor FileCloudKitSyncStateStore: CloudKitSyncStateStore {
    private let directory: URL
    public init(directory: URL = .applicationSupportDirectory.appending(path: "EZSwiftData", directoryHint: .isDirectory)) { self.directory = directory }
    public func load(containerIdentifier: String) async throws -> CloudKitSyncState? {
        let url = fileURL(containerIdentifier); guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        do { return try JSONDecoder().decode(CloudKitSyncState.self, from: Data(contentsOf: url)) }
        catch { try? FileManager.default.removeItem(at: url); return nil }
    }
    public func save(_ state: CloudKitSyncState, containerIdentifier: String) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL(containerIdentifier), options: .atomic)
    }
    public func remove(containerIdentifier: String) async throws { try? FileManager.default.removeItem(at: fileURL(containerIdentifier)) }
    private func fileURL(_ identifier: String) -> URL {
        let safe = identifier.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "_" }
        return directory.appending(path: String(safe) + ".json")
    }
}

/// Configuration for a sharing coordinator.
public struct CloudKitSharingCoordinatorConfiguration: Sendable {
    public var conflictPolicy: CloudKitConflictPolicy
    public var retryPolicy: CloudKitRetryPolicy
    public var installsSubscriptions: Bool
    public init(conflictPolicy: CloudKitConflictPolicy = .serverWins, retryPolicy: CloudKitRetryPolicy = .default, installsSubscriptions: Bool = true) {
        self.conflictPolicy = conflictPolicy; self.retryPolicy = retryPolicy; self.installsSubscriptions = installsSubscriptions
    }
}

/// Coordinates the private and shared databases, durable state, subscriptions, and event delivery.
public actor CloudKitSharingCoordinator {
    public let containerIdentifier: String
    public nonisolated let events: AsyncStream<CloudKitSyncEvent>
    private let continuation: AsyncStream<CloudKitSyncEvent>.Continuation
    private let privateStore: CloudKitSharingStore
    private let sharedStore: CloudKitSharingStore
    private let stateStore: any CloudKitSyncStateStore
    private let configuration: CloudKitSharingCoordinatorConfiguration
    private var started = false
    private var syncTask: Task<Void, Error>?

    public init(containerIdentifier: String, configuration: CloudKitSharingCoordinatorConfiguration = .init(), stateStore: any CloudKitSyncStateStore = FileCloudKitSyncStateStore()) throws {
        self.containerIdentifier = containerIdentifier; self.configuration = configuration; self.stateStore = stateStore
        privateStore = try .init(containerIdentifier: containerIdentifier, database: .privateDatabase)
        sharedStore = try .init(containerIdentifier: containerIdentifier, database: .sharedDatabase)
        let pair = AsyncStream<CloudKitSyncEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        events = pair.stream; continuation = pair.continuation
    }
    public func start() async throws {
        guard !started else { return }; started = true
        _ = try await stateStore.load(containerIdentifier: containerIdentifier) ?? .init()
        if configuration.installsSubscriptions { try await privateStore.installSubscriptions(); try await sharedStore.installSubscriptions() }
        try await synchronize()
    }
    public func stop() async { started = false; syncTask?.cancel(); syncTask = nil }
    public func synchronize() async throws {
        if let syncTask { return try await syncTask.value }
        let task = Task { [self] in
            defer { syncTask = nil }
            for (scope, store) in [(CloudKitSharingDatabase.privateDatabase, privateStore), (.sharedDatabase, sharedStore)] {
                try Task.checkCancellation(); continuation.yield(.synchronizationStarted(database: scope))
                if scope == .sharedDatabase {
                    for collaboration in try await store.collaborations() { continuation.yield(.collaborationAdded(collaboration)) }
                }
                continuation.yield(.synchronizationFinished(database: scope))
            }
        }
        syncTask = task; try await task.value
    }
    public func accept(_ metadata: CKShare.Metadata) async throws -> AcceptedCloudKitShare {
        let accepted = try await privateStore.accept(metadata); try await synchronize(); return accepted
    }
    public func collaborations() async throws -> [CloudKitCollaborationSummary] { try await sharedStore.collaborations() }
    public func processRemoteNotification(userInfo: [AnyHashable: Any]) async throws -> CloudKitNotificationResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .ignored }
        try await synchronize(); return .synchronizationScheduled(database: nil)
    }
    public func applicationBecameActive() async { do { try await synchronize() } catch { continuation.yield(.failed(.init(operation: "refresh after activation", underlyingError: error))) } }
    deinit { continuation.finish() }
}
#endif
