#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

/// A stable, `Sendable` description of a CloudKit database.
public enum CloudKitDatabaseScope: String, Codable, Sendable {
    case privateDatabase
    case sharedDatabase

    var ckScope: CKDatabase.Scope {
        switch self {
        case .privateDatabase: .private
        case .sharedDatabase: .shared
        }
    }
}

public struct CloudKitZoneIdentity: Hashable, Codable, Sendable {
    public var zoneName: String
    public var ownerName: String

    public init(zoneName: String, ownerName: String) {
        self.zoneName = zoneName
        self.ownerName = ownerName
    }

    init(_ id: CKRecordZone.ID) {
        self.init(zoneName: id.zoneName, ownerName: id.ownerName)
    }

    var ckID: CKRecordZone.ID { .init(zoneName: zoneName, ownerName: ownerName) }
}

public struct CloudKitRecordIdentity: Hashable, Codable, Sendable {
    public var recordName: String
    public var zone: CloudKitZoneIdentity

    public init(recordName: String, zone: CloudKitZoneIdentity) {
        self.recordName = recordName
        self.zone = zone
    }

    init(_ id: CKRecord.ID) {
        self.init(recordName: id.recordName, zone: .init(id.zoneID))
    }

    var ckID: CKRecord.ID { .init(recordName: recordName, zoneID: zone.ckID) }
}

/// CloudKit's opaque token represented without sending a non-Sendable framework object.
public struct CloudKitChangeToken: Hashable, Codable, Sendable {
    public let data: Data

    public init(data: Data) { self.data = data }

    init(_ token: CKServerChangeToken) throws {
        data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func decoded() throws -> CKServerChangeToken? {
        try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}

/// A record encoded using CloudKit's secure system-field representation.
public struct CloudKitRecordSnapshot: Hashable, Codable, Sendable {
    public let identity: CloudKitRecordIdentity
    public let recordType: String
    public let modificationDate: Date?
    public let encodedRecord: Data

    public init(identity: CloudKitRecordIdentity, recordType: String, modificationDate: Date?, encodedRecord: Data) {
        self.identity = identity
        self.recordType = recordType
        self.modificationDate = modificationDate
        self.encodedRecord = encodedRecord
    }

    init(record: CKRecord) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
        self.init(identity: .init(record.recordID), recordType: record.recordType,
                  modificationDate: record.modificationDate, encodedRecord: data)
    }

    func record() throws -> CKRecord {
        guard let record = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: encodedRecord) else {
            throw CloudKitSynchronizationError.invalidSnapshot
        }
        return record
    }
}

public struct CloudKitRecordDeletion: Hashable, Codable, Sendable {
    public let identity: CloudKitRecordIdentity
    public let recordType: String
    public init(identity: CloudKitRecordIdentity, recordType: String) {
        self.identity = identity
        self.recordType = recordType
    }
}

public struct CloudKitDatabaseChanges: Sendable {
    public let token: CloudKitChangeToken?
    public let changedZoneIDs: [CloudKitZoneIdentity]
    public let deletedZoneIDs: [CloudKitZoneIdentity]
    public init(token: CloudKitChangeToken?, changedZoneIDs: [CloudKitZoneIdentity], deletedZoneIDs: [CloudKitZoneIdentity]) {
        self.token = token; self.changedZoneIDs = changedZoneIDs; self.deletedZoneIDs = deletedZoneIDs
    }
}

public struct CloudKitZoneChanges: Sendable {
    public let tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    public let changedRecords: [CloudKitRecordSnapshot]
    public let deletedRecords: [CloudKitRecordDeletion]
    public init(tokens: [CloudKitZoneIdentity: CloudKitChangeToken], changedRecords: [CloudKitRecordSnapshot], deletedRecords: [CloudKitRecordDeletion]) {
        self.tokens = tokens; self.changedRecords = changedRecords; self.deletedRecords = deletedRecords
    }
}

public struct CloudKitBatchItemResult: Sendable {
    public let identity: CloudKitRecordIdentity
    public let result: Result<CloudKitRecordSnapshot?, CloudKitOperationFailure>
}

public struct CloudKitOperationFailure: Error, Hashable, Codable, Sendable {
    public let code: Int
    public let message: String
    public let clientRecord: CloudKitRecordSnapshot?
    public let serverRecord: CloudKitRecordSnapshot?
    public init(code: Int, message: String, clientRecord: CloudKitRecordSnapshot? = nil, serverRecord: CloudKitRecordSnapshot? = nil) {
        self.code = code; self.message = message; self.clientRecord = clientRecord; self.serverRecord = serverRecord
    }
}

public protocol CloudKitClient: Sendable {
    func fetchDatabaseChanges(scope: CloudKitDatabaseScope, since token: CloudKitChangeToken?) async throws -> CloudKitDatabaseChanges
    func fetchRecordZoneChanges(scope: CloudKitDatabaseScope, zoneIDs: [CloudKitZoneIdentity], tokens: [CloudKitZoneIdentity: CloudKitChangeToken]) async throws -> CloudKitZoneChanges
    func save(records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async throws -> [CloudKitBatchItemResult]
    func delete(recordIDs: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope) async throws -> [CloudKitBatchItemResult]
}

/// The production client. Operations are deliberately used instead of query-based
/// scans so CloudKit can return only changes after each opaque token.
public actor LiveCloudKitClient: CloudKitClient {
    private let container: CKContainer

    public init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    private func database(_ scope: CloudKitDatabaseScope) -> CKDatabase {
        switch scope {
        case .privateDatabase: container.privateCloudDatabase
        case .sharedDatabase: container.sharedCloudDatabase
        }
    }

    public func fetchDatabaseChanges(scope: CloudKitDatabaseScope, since token: CloudKitChangeToken?) async throws -> CloudKitDatabaseChanges {
        let previous = try token?.decoded()
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: previous)
            let collector = DatabaseChangeCollector()
            operation.recordZoneWithIDChangedBlock = { id in Task { await collector.changed(id) } }
            operation.recordZoneWithIDWasDeletedBlock = { id, _ in Task { await collector.deleted(id) } }
            operation.changeTokenUpdatedBlock = { token in Task { await collector.token(token) } }
            operation.fetchDatabaseChangesResultBlock = { result in
                Task {
                    switch result {
                    case let .success((token, _)):
                        await collector.token(token)
                        continuation.resume(returning: try await collector.value())
                    case let .failure(error): continuation.resume(throwing: error)
                    }
                }
            }
            database(scope).add(operation)
        }
    }

    public func fetchRecordZoneChanges(scope: CloudKitDatabaseScope, zoneIDs: [CloudKitZoneIdentity], tokens: [CloudKitZoneIdentity: CloudKitChangeToken]) async throws -> CloudKitZoneChanges {
        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for zone in zoneIDs {
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = try tokens[zone]?.decoded()
            configurations[zone.ckID] = configuration
        }
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs.map(\.ckID), configurationsByRecordZoneID: configurations)
            let collector = ZoneChangeCollector()
            operation.recordWasChangedBlock = { _, result in
                Task { if case let .success(record) = result { try await collector.changed(record) } }
            }
            operation.recordWithIDWasDeletedBlock = { id, type in Task { await collector.deleted(id, type: type) } }
            operation.recordZoneChangeTokensUpdatedBlock = { id, token, _ in
                Task { if let token { try await collector.token(token, zone: id) } }
            }
            operation.recordZoneFetchResultBlock = { id, result in
                Task { if case let .success((token, _, _)) = result, let token { try await collector.token(token, zone: id) } }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                Task {
                    switch result {
                    case .success: continuation.resume(returning: await collector.value())
                    case let .failure(error): continuation.resume(throwing: error)
                    }
                }
            }
            database(scope).add(operation)
        }
    }

    public func save(records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async throws -> [CloudKitBatchItemResult] {
        try await modify(saving: records, deleting: [], scope: scope)
    }

    public func delete(recordIDs: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope) async throws -> [CloudKitBatchItemResult] {
        try await modify(saving: [], deleting: recordIDs, scope: scope)
    }

    private func modify(saving: [CloudKitRecordSnapshot], deleting: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope) async throws -> [CloudKitBatchItemResult] {
        var all: [CloudKitBatchItemResult] = []
        let entries = saving.map { (snapshot: $0, deletion: Optional<CloudKitRecordIdentity>.none) }
            + deleting.map { (snapshot: Optional<CloudKitRecordSnapshot>.none, deletion: $0) }
        for start in stride(from: 0, to: entries.count, by: 400) {
            let chunk = entries[start..<min(start + 400, entries.count)]
            let saves = try chunk.compactMap(\.snapshot).map { try $0.record() }
            let deletes = chunk.compactMap(\.deletion).map(\.ckID)
            let results: [CloudKitBatchItemResult] = await withCheckedContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: saves, recordIDsToDelete: deletes)
                operation.savePolicy = .ifServerRecordUnchanged
                let collector = ModifyCollector()
                operation.perRecordSaveBlock = { id, result in Task { await collector.saved(id, result: result) } }
                operation.perRecordDeleteBlock = { id, result in Task { await collector.deleted(id, result: result) } }
                operation.modifyRecordsResultBlock = { _ in Task { continuation.resume(returning: await collector.value()) } }
                database(scope).add(operation)
            }
            all += results
        }
        return all
    }
}

private actor DatabaseChangeCollector {
    var changedZones: [CloudKitZoneIdentity] = []
    var deletedZones: [CloudKitZoneIdentity] = []
    var latestToken: CKServerChangeToken?
    func changed(_ id: CKRecordZone.ID) { changedZones.append(.init(id)) }
    func deleted(_ id: CKRecordZone.ID) { deletedZones.append(.init(id)) }
    func token(_ token: CKServerChangeToken) { latestToken = token }
    func value() throws -> CloudKitDatabaseChanges {
        try .init(token: latestToken.map(CloudKitChangeToken.init), changedZoneIDs: changedZones, deletedZoneIDs: deletedZones)
    }
}

private actor ZoneChangeCollector {
    var tokens: [CloudKitZoneIdentity: CloudKitChangeToken] = [:]
    var changedRecords: [CloudKitRecordSnapshot] = []
    var deletedRecords: [CloudKitRecordDeletion] = []
    func changed(_ record: CKRecord) throws { changedRecords.append(try .init(record: record)) }
    func deleted(_ id: CKRecord.ID, type: String) { deletedRecords.append(.init(identity: .init(id), recordType: type)) }
    func token(_ token: CKServerChangeToken, zone: CKRecordZone.ID) throws { tokens[.init(zone)] = try .init(token) }
    func value() -> CloudKitZoneChanges { .init(tokens: tokens, changedRecords: changedRecords, deletedRecords: deletedRecords) }
}

private actor ModifyCollector {
    var results: [CloudKitBatchItemResult] = []
    func saved(_ id: CKRecord.ID, result: Result<CKRecord, any Error>) {
        do { results.append(.init(identity: .init(id), result: .success(try .init(record: result.get())))) }
        catch { results.append(.init(identity: .init(id), result: .failure(.init(error)))) }
    }
    func deleted(_ id: CKRecord.ID, result: Result<Void, any Error>) {
        switch result {
        case .success: results.append(.init(identity: .init(id), result: .success(nil)))
        case let .failure(error): results.append(.init(identity: .init(id), result: .failure(.init(error))))
        }
    }
    func value() -> [CloudKitBatchItemResult] { results }
}

private extension CloudKitOperationFailure {
    init(_ error: any Error) {
        let nsError = error as NSError
        let ckError = error as? CKError
        self.init(
            code: nsError.code,
            message: nsError.localizedDescription,
            clientRecord: try? (ckError?.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord).map(CloudKitRecordSnapshot.init),
            serverRecord: try? (ckError?.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord).map(CloudKitRecordSnapshot.init)
        )
    }
}

public enum CloudKitSynchronizationError: Error, Sendable { case invalidSnapshot }

public struct CloudKitSyncState: Codable, Equatable, Sendable {
    public var privateDatabaseToken: CloudKitChangeToken?
    public var sharedDatabaseToken: CloudKitChangeToken?
    public var zoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    public var knownSharedZoneKeys: Set<CloudKitZoneIdentity>

    public init(privateDatabaseToken: CloudKitChangeToken? = nil, sharedDatabaseToken: CloudKitChangeToken? = nil,
                zoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken] = [:], knownSharedZoneKeys: Set<CloudKitZoneIdentity> = []) {
        self.privateDatabaseToken = privateDatabaseToken; self.sharedDatabaseToken = sharedDatabaseToken
        self.zoneTokens = zoneTokens; self.knownSharedZoneKeys = knownSharedZoneKeys
    }
}

public protocol CloudKitSyncStateStore: Sendable {
    func load(containerIdentifier: String) async throws -> CloudKitSyncState
    func save(_ state: CloudKitSyncState, containerIdentifier: String) async throws
}

public actor InMemoryCloudKitSyncStateStore: CloudKitSyncStateStore {
    private var states: [String: CloudKitSyncState] = [:]
    public init() {}
    public func load(containerIdentifier: String) -> CloudKitSyncState { states[containerIdentifier] ?? .init() }
    public func save(_ state: CloudKitSyncState, containerIdentifier: String) { states[containerIdentifier] = state }
}

public enum CloudKitConflictPolicy: Sendable {
    case serverWins
    case clientWins
    case newestModificationDateWins
    case custom(@Sendable (CloudKitRecordSnapshot, CloudKitRecordSnapshot) async -> CloudKitRecordSnapshot)

    public func resolve(client: CloudKitRecordSnapshot, server: CloudKitRecordSnapshot) async -> CloudKitRecordSnapshot {
        switch self {
        case .serverWins: server
        case .clientWins: client
        case .newestModificationDateWins:
            (client.modificationDate ?? .distantPast) >= (server.modificationDate ?? .distantPast) ? client : server
        case let .custom(resolver): await resolver(client, server)
        }
    }
}

public enum CloudKitSyncEvent: Sendable {
    case synchronizationStarted
    case synchronizationFinished
    case recordsChanged([CloudKitRecordSnapshot])
    case recordsDeleted([CloudKitRecordDeletion])
    case collaborationAdded(CloudKitZoneIdentity)
    case collaborationRemoved(CloudKitZoneIdentity)
    case conflict(client: CloudKitRecordSnapshot, server: CloudKitRecordSnapshot)
    case failure(CloudKitOperationFailure)
}

public enum CloudKitRemoteNotificationResult: Equatable, Sendable {
    case ignored
    case synchronizationScheduled(database: CloudKitDatabaseScope)
}

public struct CloudKitSharingConfiguration: Sendable {
    public var conflictPolicy: CloudKitConflictPolicy
    public init(conflictPolicy: CloudKitConflictPolicy = .serverWins) { self.conflictPolicy = conflictPolicy }
}

public actor CloudKitSharingCoordinator {
    public let containerIdentifier: String
    private let client: any CloudKitClient
    private let stateStore: any CloudKitSyncStateStore
    private let configuration: CloudKitSharingConfiguration
    private var pushSynchronizationTask: Task<Void, Never>?

    public init(containerIdentifier: String, client: any CloudKitClient, stateStore: any CloudKitSyncStateStore,
                configuration: CloudKitSharingConfiguration = .init()) {
        self.containerIdentifier = containerIdentifier; self.client = client
        self.stateStore = stateStore; self.configuration = configuration
    }

    public func synchronize() -> AsyncStream<CloudKitSyncEvent> {
        AsyncStream { continuation in
            let task = Task { await self.runSynchronization(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Validates the subscription rather than treating every CloudKit push as ours.
    /// Multiple pushes arriving before the scheduled task starts share one sync pass.
    public func processRemoteNotification(userInfo: [AnyHashable: Any]) -> CloudKitRemoteNotificationResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let subscriptionID = notification.subscriptionID else { return .ignored }
        let prefix = "com.ezswiftdata.sharing.\(containerIdentifier)."
        let scope: CloudKitDatabaseScope
        switch subscriptionID {
        case prefix + CloudKitDatabaseScope.privateDatabase.rawValue: scope = .privateDatabase
        case prefix + CloudKitDatabaseScope.sharedDatabase.rawValue: scope = .sharedDatabase
        default: return .ignored
        }
        if pushSynchronizationTask == nil {
            pushSynchronizationTask = Task {
                await Task.yield()
                for await _ in self.synchronize() {}
                self.pushSynchronizationDidFinish()
            }
        }
        return .synchronizationScheduled(database: scope)
    }

    private func pushSynchronizationDidFinish() { pushSynchronizationTask = nil }

    /// Saves records and resolves optimistic-lock conflicts individually without
    /// discarding successful siblings in the same operation.
    public func save(_ records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async -> [CloudKitBatchItemResult] {
        do {
            let initial = try await client.save(records: records, scope: scope)
            var final = initial
            for index in final.indices {
                guard case let .failure(failure) = final[index].result,
                      failure.code == CKError.serverRecordChanged.rawValue,
                      let clientRecord = failure.clientRecord,
                      let serverRecord = failure.serverRecord else { continue }
                let resolved = await configuration.conflictPolicy.resolve(client: clientRecord, server: serverRecord)
                if let retry = try? await client.save(records: [resolved], scope: scope).first {
                    final[index] = retry
                }
            }
            return final
        } catch {
            let failure = CloudKitOperationFailure(error)
            return records.map { .init(identity: $0.identity, result: .failure(failure)) }
        }
    }

    private func runSynchronization(_ output: AsyncStream<CloudKitSyncEvent>.Continuation) async {
        output.yield(.synchronizationStarted)
        do {
            var state = try await stateStore.load(containerIdentifier: containerIdentifier)
            for scope in [CloudKitDatabaseScope.privateDatabase, .sharedDatabase] {
                try await synchronize(scope, state: &state, output: output)
                try await stateStore.save(state, containerIdentifier: containerIdentifier)
            }
            output.yield(.synchronizationFinished)
        } catch {
            let nsError = error as NSError
            output.yield(.failure(.init(code: nsError.code, message: nsError.localizedDescription)))
        }
        output.finish()
    }

    private func synchronize(_ scope: CloudKitDatabaseScope, state: inout CloudKitSyncState,
                             output: AsyncStream<CloudKitSyncEvent>.Continuation) async throws {
        var databaseToken = scope == .privateDatabase ? state.privateDatabaseToken : state.sharedDatabaseToken
        let databaseChanges: CloudKitDatabaseChanges
        do {
            databaseChanges = try await client.fetchDatabaseChanges(scope: scope, since: databaseToken)
        } catch let error as CKError where error.code == .changeTokenExpired {
            databaseToken = nil
            databaseChanges = try await client.fetchDatabaseChanges(scope: scope, since: nil)
        }
        if scope == .privateDatabase { state.privateDatabaseToken = databaseChanges.token }
        else { state.sharedDatabaseToken = databaseChanges.token }

        for zone in databaseChanges.deletedZoneIDs {
            state.zoneTokens.removeValue(forKey: zone)
            if state.knownSharedZoneKeys.remove(zone) != nil { output.yield(.collaborationRemoved(zone)) }
        }
        if scope == .sharedDatabase {
            for zone in databaseChanges.changedZoneIDs where state.knownSharedZoneKeys.insert(zone).inserted {
                output.yield(.collaborationAdded(zone))
            }
        }
        guard !databaseChanges.changedZoneIDs.isEmpty else { return }

        let changes: CloudKitZoneChanges
        do {
            changes = try await client.fetchRecordZoneChanges(scope: scope, zoneIDs: databaseChanges.changedZoneIDs, tokens: state.zoneTokens)
        } catch let error as CKError where error.code == .changeTokenExpired {
            for zone in databaseChanges.changedZoneIDs { state.zoneTokens.removeValue(forKey: zone) }
            changes = try await client.fetchRecordZoneChanges(scope: scope, zoneIDs: databaseChanges.changedZoneIDs, tokens: [:])
        }
        state.zoneTokens.merge(changes.tokens) { _, new in new }
        if !changes.changedRecords.isEmpty { output.yield(.recordsChanged(changes.changedRecords)) }
        if !changes.deletedRecords.isEmpty { output.yield(.recordsDeleted(changes.deletedRecords)) }
    }
}
#endif
