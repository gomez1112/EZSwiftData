#if canImport(CloudKit)
  @preconcurrency import CloudKit
  import Foundation

  /// A stable, `Sendable` description of a CloudKit database.
  public enum CloudKitDatabaseScope: String, Codable, Hashable, Sendable {
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

    public init(
      identity: CloudKitRecordIdentity, recordType: String, modificationDate: Date?,
      encodedRecord: Data
    ) {
      self.identity = identity
      self.recordType = recordType
      self.modificationDate = modificationDate
      self.encodedRecord = encodedRecord
    }

    init(record: CKRecord) throws {
      let data = try NSKeyedArchiver.archivedData(
        withRootObject: record, requiringSecureCoding: true)
      self.init(
        identity: .init(record.recordID), recordType: record.recordType,
        modificationDate: record.modificationDate, encodedRecord: data)
    }

    func record() throws -> CKRecord {
      guard
        let record = try NSKeyedUnarchiver.unarchivedObject(
          ofClass: CKRecord.self, from: encodedRecord)
      else {
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
    public init(
      token: CloudKitChangeToken?, changedZoneIDs: [CloudKitZoneIdentity],
      deletedZoneIDs: [CloudKitZoneIdentity]
    ) {
      self.token = token
      self.changedZoneIDs = changedZoneIDs
      self.deletedZoneIDs = deletedZoneIDs
    }
  }

  public struct CloudKitZoneChanges: Sendable {
    public let tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    public let changedRecords: [CloudKitRecordSnapshot]
    public let deletedRecords: [CloudKitRecordDeletion]
    public init(
      tokens: [CloudKitZoneIdentity: CloudKitChangeToken], changedRecords: [CloudKitRecordSnapshot],
      deletedRecords: [CloudKitRecordDeletion]
    ) {
      self.tokens = tokens
      self.changedRecords = changedRecords
      self.deletedRecords = deletedRecords
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
    public init(
      code: Int, message: String, clientRecord: CloudKitRecordSnapshot? = nil,
      serverRecord: CloudKitRecordSnapshot? = nil
    ) {
      self.code = code
      self.message = message
      self.clientRecord = clientRecord
      self.serverRecord = serverRecord
    }
  }

  public protocol CloudKitClient: Sendable {
    func fetchDatabaseChanges(scope: CloudKitDatabaseScope, since token: CloudKitChangeToken?)
      async throws -> CloudKitDatabaseChanges
    func fetchRecordZoneChanges(
      scope: CloudKitDatabaseScope, zoneIDs: [CloudKitZoneIdentity],
      tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    ) async throws -> CloudKitZoneChanges
    func save(records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async throws
      -> [CloudKitBatchItemResult]
    func delete(recordIDs: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope) async throws
      -> [CloudKitBatchItemResult]
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

    public func fetchDatabaseChanges(
      scope: CloudKitDatabaseScope, since token: CloudKitChangeToken?
    ) async throws -> CloudKitDatabaseChanges {
      var previous = try token?.decoded()
      let collector = DatabaseChangeCollector()
      var moreComing = true
      while moreComing {
        let page = try await fetchDatabaseChangesPage(
          scope: scope,
          previous: previous,
          collector: collector
        )
        previous = page.token
        moreComing = page.moreComing
      }
      return try collector.value()
    }

    private func fetchDatabaseChangesPage(
      scope: CloudKitDatabaseScope,
      previous: CKServerChangeToken?,
      collector: DatabaseChangeCollector
    ) async throws -> (token: CKServerChangeToken, moreComing: Bool) {
      try await withCheckedThrowingContinuation { continuation in
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: previous)
        operation.recordZoneWithIDChangedBlock = collector.changed
        operation.recordZoneWithIDWasDeletedBlock = { id, _ in collector.deleted(id) }
        operation.changeTokenUpdatedBlock = collector.token
        operation.fetchDatabaseChangesResultBlock = { result in
          switch result {
          case let .success((token, moreComing)):
            collector.token(token)
            continuation.resume(returning: (token, moreComing))
          case let .failure(error):
            continuation.resume(throwing: error)
          }
        }
        database(scope).add(operation)
      }
    }

    public func fetchRecordZoneChanges(
      scope: CloudKitDatabaseScope, zoneIDs: [CloudKitZoneIdentity],
      tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    ) async throws -> CloudKitZoneChanges {
      var previousTokens: [CloudKitZoneIdentity: CKServerChangeToken] = [:]
      for zone in zoneIDs {
        if let token = try tokens[zone]?.decoded() { previousTokens[zone] = token }
      }
      let collector = ZoneChangeCollector()
      var pendingZones = Set(zoneIDs)
      while !pendingZones.isEmpty {
        pendingZones = try await fetchRecordZoneChangesPage(
          scope: scope,
          zones: pendingZones,
          previousTokens: &previousTokens,
          collector: collector
        )
      }
      return try collector.value()
    }

    private func fetchRecordZoneChangesPage(
      scope: CloudKitDatabaseScope,
      zones: Set<CloudKitZoneIdentity>,
      previousTokens: inout [CloudKitZoneIdentity: CKServerChangeToken],
      collector: ZoneChangeCollector
    ) async throws -> Set<CloudKitZoneIdentity> {
      var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] =
        [:]
      for zone in zones {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = previousTokens[zone]
        configurations[zone.ckID] = configuration
      }
      let page = try await withCheckedThrowingContinuation { continuation in
        let pageState = ZonePageState()
        let operation = CKFetchRecordZoneChangesOperation(
          recordZoneIDs: zones.map(\.ckID), configurationsByRecordZoneID: configurations)
        operation.recordWasChangedBlock = { _, result in
          switch result {
          case let .success(record): collector.changed(record)
          case let .failure(error): collector.fail(error)
          }
        }
        operation.recordWithIDWasDeletedBlock = collector.deleted
        operation.recordZoneChangeTokensUpdatedBlock = { id, token, _ in
          if let token { collector.token(token, zone: id) }
        }
        operation.recordZoneFetchResultBlock = { id, result in
          switch result {
          case let .success((token, _, moreComing)):
            if let token { collector.token(token, zone: id) }
            pageState.finished(zone: id, token: token, moreComing: moreComing)
          case let .failure(error): collector.fail(error)
          }
        }
        operation.fetchRecordZoneChangesResultBlock = { result in
          switch result {
          case .success:
            do {
              try collector.checkForError()
              continuation.resume(returning: pageState.value())
            } catch { continuation.resume(throwing: error) }
          case let .failure(error): continuation.resume(throwing: error)
          }
        }
        database(scope).add(operation)
      }
      for (zone, token) in page.tokens { previousTokens[zone] = token }
      return page.moreComing
    }

    public func save(records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async throws
      -> [CloudKitBatchItemResult]
    {
      try await modify(saving: records, deleting: [], scope: scope)
    }

    public func delete(recordIDs: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope)
      async throws -> [CloudKitBatchItemResult]
    {
      try await modify(saving: [], deleting: recordIDs, scope: scope)
    }

    private func modify(
      saving: [CloudKitRecordSnapshot], deleting: [CloudKitRecordIdentity],
      scope: CloudKitDatabaseScope
    ) async throws -> [CloudKitBatchItemResult] {
      var all: [CloudKitBatchItemResult] = []
      let entries =
        saving.map { (snapshot: $0, deletion: Optional<CloudKitRecordIdentity>.none) }
        + deleting.map { (snapshot: Optional<CloudKitRecordSnapshot>.none, deletion: $0) }
      for start in stride(from: 0, to: entries.count, by: 400) {
        let chunk = entries[start..<min(start + 400, entries.count)]
        let saves = try chunk.compactMap(\.snapshot).map { try $0.record() }
        let deletes = chunk.compactMap(\.deletion).map(\.ckID)
        let results: [CloudKitBatchItemResult] = await withCheckedContinuation { continuation in
          let operation = CKModifyRecordsOperation(recordsToSave: saves, recordIDsToDelete: deletes)
          operation.savePolicy = .ifServerRecordUnchanged
          let collector = ModifyCollector()
          operation.perRecordSaveBlock = collector.saved
          operation.perRecordDeleteBlock = collector.deleted
          operation.modifyRecordsResultBlock = { result in
            let operationError: (any Error)?
            switch result {
            case .success: operationError = nil
            case let .failure(error): operationError = error
            }
            continuation.resume(
              returning: collector.value(
                orderedBy: chunk.compactMap { $0.snapshot?.identity ?? $0.deletion },
                operationError: operationError
              ))
          }
          database(scope).add(operation)
        }
        all += results
      }
      return all
    }
  }

  private final class DatabaseChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var changedZones: [CloudKitZoneIdentity] = []
    private var deletedZones: [CloudKitZoneIdentity] = []
    private var latestToken: CKServerChangeToken?
    func changed(_ id: CKRecordZone.ID) { lock.withLock { changedZones.append(.init(id)) } }
    func deleted(_ id: CKRecordZone.ID) { lock.withLock { deletedZones.append(.init(id)) } }
    func token(_ token: CKServerChangeToken) { lock.withLock { latestToken = token } }
    func value() throws -> CloudKitDatabaseChanges {
      try lock.withLock {
        try .init(
          token: latestToken.map(CloudKitChangeToken.init), changedZoneIDs: changedZones,
          deletedZoneIDs: deletedZones)
      }
    }
  }

  private final class ZoneChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [CloudKitZoneIdentity: CloudKitChangeToken] = [:]
    private var changedRecords: [CloudKitRecordSnapshot] = []
    private var deletedRecords: [CloudKitRecordDeletion] = []
    private var firstError: (any Error)?
    func changed(_ record: CKRecord) {
      lock.withLock {
        do { changedRecords.append(try .init(record: record)) } catch {
          firstError = firstError ?? error
        }
      }
    }
    func deleted(_ id: CKRecord.ID, type: String) {
      lock.withLock { deletedRecords.append(.init(identity: .init(id), recordType: type)) }
    }
    func token(_ token: CKServerChangeToken, zone: CKRecordZone.ID) {
      lock.withLock {
        do { tokens[.init(zone)] = try .init(token) } catch { firstError = firstError ?? error }
      }
    }
    func fail(_ error: any Error) { lock.withLock { firstError = firstError ?? error } }
    func checkForError() throws { try lock.withLock { if let firstError { throw firstError } } }
    func value() throws -> CloudKitZoneChanges {
      try lock.withLock {
        if let firstError { throw firstError }
        return .init(tokens: tokens, changedRecords: changedRecords, deletedRecords: deletedRecords)
      }
    }
  }

  private final class ZonePageState: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [CloudKitZoneIdentity: CKServerChangeToken] = [:]
    private var moreComing: Set<CloudKitZoneIdentity> = []

    func finished(zone: CKRecordZone.ID, token: CKServerChangeToken?, moreComing: Bool) {
      lock.withLock {
        let identity = CloudKitZoneIdentity(zone)
        if let token { tokens[identity] = token }
        if moreComing { self.moreComing.insert(identity) }
      }
    }

    func value() -> (
      tokens: [CloudKitZoneIdentity: CKServerChangeToken], moreComing: Set<CloudKitZoneIdentity>
    ) {
      lock.withLock { (tokens, moreComing) }
    }
  }

  private final class ModifyCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [CloudKitRecordIdentity: CloudKitBatchItemResult] = [:]
    func saved(_ id: CKRecord.ID, result: Result<CKRecord, any Error>) {
      let item: CloudKitBatchItemResult
      do {
        item = .init(identity: .init(id), result: .success(try .init(record: result.get())))
      } catch { item = .init(identity: .init(id), result: .failure(.init(error))) }
      lock.withLock { results[item.identity] = item }
    }
    func deleted(_ id: CKRecord.ID, result: Result<Void, any Error>) {
      let item =
        switch result {
        case .success: CloudKitBatchItemResult(identity: .init(id), result: .success(nil))
        case let .failure(error):
          CloudKitBatchItemResult(identity: .init(id), result: .failure(.init(error)))
        }
      lock.withLock { results[item.identity] = item }
    }
    func value(orderedBy identities: [CloudKitRecordIdentity], operationError: (any Error)?)
      -> [CloudKitBatchItemResult]
    {
      lock.withLock {
        identities.map { identity in
          results[identity]
            ?? .init(
              identity: identity,
              result: .failure(
                .init(operationError ?? CloudKitSynchronizationError.missingOperationResult))
            )
        }
      }
    }
  }

  extension CloudKitOperationFailure {
    fileprivate init(_ error: any Error) {
      let nsError = error as NSError
      let ckError = error as? CKError
      self.init(
        code: nsError.code,
        message: nsError.localizedDescription,
        clientRecord: try? (ckError?.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord)
          .map(CloudKitRecordSnapshot.init),
        serverRecord: try? (ckError?.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord)
          .map(CloudKitRecordSnapshot.init)
      )
    }
  }

  public enum CloudKitSynchronizationError: Error, Sendable {
    case invalidSnapshot
    case missingOperationResult
  }

  public struct CloudKitSyncState: Codable, Equatable, Sendable {
    public var privateDatabaseToken: CloudKitChangeToken?
    public var sharedDatabaseToken: CloudKitChangeToken?
    public var zoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    /// Private-database zone tokens. Kept separate because an owner can use the
    /// same zone identifier in both the private and shared databases.
    public var privateZoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    public var knownSharedZoneKeys: Set<CloudKitZoneIdentity>

    private enum CodingKeys: String, CodingKey {
      case privateDatabaseToken
      case sharedDatabaseToken
      case zoneTokens
      case privateZoneTokens
      case knownSharedZoneKeys
    }

    public init(
      privateDatabaseToken: CloudKitChangeToken? = nil,
      sharedDatabaseToken: CloudKitChangeToken? = nil,
      zoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken] = [:],
      privateZoneTokens: [CloudKitZoneIdentity: CloudKitChangeToken] = [:],
      knownSharedZoneKeys: Set<CloudKitZoneIdentity> = []
    ) {
      self.privateDatabaseToken = privateDatabaseToken
      self.sharedDatabaseToken = sharedDatabaseToken
      self.zoneTokens = zoneTokens
      self.privateZoneTokens = privateZoneTokens
      self.knownSharedZoneKeys = knownSharedZoneKeys
    }

    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      privateDatabaseToken = try values.decodeIfPresent(
        CloudKitChangeToken.self, forKey: .privateDatabaseToken)
      sharedDatabaseToken = try values.decodeIfPresent(
        CloudKitChangeToken.self, forKey: .sharedDatabaseToken)
      zoneTokens =
        try values.decodeIfPresent(
          [CloudKitZoneIdentity: CloudKitChangeToken].self, forKey: .zoneTokens) ?? [:]
      privateZoneTokens =
        try values.decodeIfPresent(
          [CloudKitZoneIdentity: CloudKitChangeToken].self, forKey: .privateZoneTokens) ?? [:]
      knownSharedZoneKeys =
        try values.decodeIfPresent(Set<CloudKitZoneIdentity>.self, forKey: .knownSharedZoneKeys)
        ?? []
    }
  }

  public protocol CloudKitSyncStateStore: Sendable {
    func load(containerIdentifier: String) async throws -> CloudKitSyncState
    func save(_ state: CloudKitSyncState, containerIdentifier: String) async throws
    func remove(containerIdentifier: String) async throws
  }

  extension CloudKitSyncStateStore {
    public func remove(containerIdentifier: String) async throws {}
  }

  public actor InMemoryCloudKitSyncStateStore: CloudKitSyncStateStore {
    private var states: [String: CloudKitSyncState] = [:]
    public init() {}
    public func load(containerIdentifier: String) -> CloudKitSyncState {
      states[containerIdentifier] ?? .init()
    }
    public func save(_ state: CloudKitSyncState, containerIdentifier: String) {
      states[containerIdentifier] = state
    }
    public func remove(containerIdentifier: String) {
      states.removeValue(forKey: containerIdentifier)
    }
  }

  public enum CloudKitConflictPolicy: Sendable {
    case serverWins
    case clientWins
    case newestModificationDateWins
    case custom(
      @Sendable (CloudKitRecordSnapshot, CloudKitRecordSnapshot) async -> CloudKitRecordSnapshot)

    public func resolve(client: CloudKitRecordSnapshot, server: CloudKitRecordSnapshot) async
      -> CloudKitRecordSnapshot
    {
      switch self {
      case .serverWins: server
      case .clientWins: client
      case .newestModificationDateWins:
        (client.modificationDate ?? .distantPast) >= (server.modificationDate ?? .distantPast)
          ? client : server
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
    public init(conflictPolicy: CloudKitConflictPolicy = .serverWins) {
      self.conflictPolicy = conflictPolicy
    }
  }

  public actor CloudKitSharingCoordinator {
    public let containerIdentifier: String
    private let client: any CloudKitClient
    private let stateStore: any CloudKitSyncStateStore
    private let configuration: CloudKitSharingConfiguration
    private var pushSynchronizationTask: Task<Void, Never>?
    private var needsAdditionalPushPass = false
    private let eventContinuation: AsyncStream<CloudKitSyncEvent>.Continuation
    /// Events that originate outside a synchronization pass, including save conflicts.
    public nonisolated let events: AsyncStream<CloudKitSyncEvent>

    public init(
      containerIdentifier: String, client: any CloudKitClient,
      stateStore: any CloudKitSyncStateStore,
      configuration: CloudKitSharingConfiguration = .init()
    ) {
      self.containerIdentifier = containerIdentifier
      self.client = client
      self.stateStore = stateStore
      self.configuration = configuration
      let eventChannel = AsyncStream<CloudKitSyncEvent>.makeStream()
      self.events = eventChannel.stream
      self.eventContinuation = eventChannel.continuation
    }

    public func synchronize() -> AsyncStream<CloudKitSyncEvent> {
      AsyncStream { continuation in
        let task = Task { await self.runSynchronization(continuation) }
        continuation.onTermination = { _ in task.cancel() }
      }
    }

    /// Validates the subscription rather than treating every CloudKit push as ours.
    /// A burst during an active pass is coalesced into one follow-up pass. Both scopes are
    /// synchronized because database changes can accompany a push for either subscription;
    /// the returned scope identifies which subscription triggered the work.
    public func processRemoteNotification(userInfo: [AnyHashable: Any])
      -> CloudKitRemoteNotificationResult
    {
      guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
        let subscriptionID = notification.subscriptionID
      else { return .ignored }
      let prefix = "com.ezswiftdata.sharing.\(containerIdentifier)."
      let scope: CloudKitDatabaseScope
      switch subscriptionID {
      case prefix + CloudKitDatabaseScope.privateDatabase.rawValue: scope = .privateDatabase
      case prefix + CloudKitDatabaseScope.sharedDatabase.rawValue: scope = .sharedDatabase
      default: return .ignored
      }
      if pushSynchronizationTask == nil {
        startPushSynchronization()
      } else {
        needsAdditionalPushPass = true
      }
      return .synchronizationScheduled(database: scope)
    }

    private func startPushSynchronization() {
      pushSynchronizationTask = Task {
        await Task.yield()
        for await _ in self.synchronize() {}
        self.pushSynchronizationDidFinish()
      }
    }

    private func pushSynchronizationDidFinish() {
      pushSynchronizationTask = nil
      guard needsAdditionalPushPass else { return }
      needsAdditionalPushPass = false
      startPushSynchronization()
    }

    /// Saves records and resolves optimistic-lock conflicts individually without
    /// discarding successful siblings in the same operation.
    public func save(_ records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) async
      -> [CloudKitBatchItemResult]
    {
      do {
        let initial = try await client.save(records: records, scope: scope)
        var final = initial
        for index in final.indices {
          guard case let .failure(failure) = final[index].result,
            failure.code == CKError.serverRecordChanged.rawValue,
            let clientRecord = failure.clientRecord,
            let serverRecord = failure.serverRecord
          else { continue }
          eventContinuation.yield(.conflict(client: clientRecord, server: serverRecord))
          let resolved = await configuration.conflictPolicy.resolve(
            client: clientRecord, server: serverRecord)
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
      var state: CloudKitSyncState
      do {
        state = try await stateStore.load(containerIdentifier: containerIdentifier)
      } catch {
        output.yield(.failure(.init(error)))
        output.finish()
        return
      }
      for scope in [CloudKitDatabaseScope.privateDatabase, .sharedDatabase] {
        do {
          try await synchronize(scope, state: &state, output: output)
        } catch {
          output.yield(.failure(.init(error)))
        }
        do {
          try await stateStore.save(state, containerIdentifier: containerIdentifier)
        } catch {
          output.yield(.failure(.init(error)))
        }
      }
      output.yield(.synchronizationFinished)
      output.finish()
    }

    private func synchronize(
      _ scope: CloudKitDatabaseScope, state: inout CloudKitSyncState,
      output: AsyncStream<CloudKitSyncEvent>.Continuation
    ) async throws {
      var databaseToken =
        scope == .privateDatabase ? state.privateDatabaseToken : state.sharedDatabaseToken
      let databaseChanges: CloudKitDatabaseChanges
      do {
        databaseChanges = try await client.fetchDatabaseChanges(scope: scope, since: databaseToken)
      } catch let error as CKError where error.code == .changeTokenExpired {
        databaseToken = nil
        databaseChanges = try await client.fetchDatabaseChanges(scope: scope, since: nil)
      }
      if scope == .privateDatabase {
        state.privateDatabaseToken = databaseChanges.token
      } else {
        state.sharedDatabaseToken = databaseChanges.token
      }

      let deletedZones = Set(databaseChanges.deletedZoneIDs)
      for zone in deletedZones {
        switch scope {
        case .privateDatabase: state.privateZoneTokens.removeValue(forKey: zone)
        case .sharedDatabase: state.zoneTokens.removeValue(forKey: zone)
        }
        if state.knownSharedZoneKeys.remove(zone) != nil {
          output.yield(.collaborationRemoved(zone))
        }
      }
      // A zone can be reported more than once across paginated database-change
      // callbacks, and a later deletion supersedes an earlier change. Passing
      // either duplicate or deleted IDs to the zone-change operation can make
      // the entire synchronization fail instead of processing the live zones.
      let changedZones = Array(Set(databaseChanges.changedZoneIDs).subtracting(deletedZones))
      if scope == .sharedDatabase {
        for zone in changedZones
        where state.knownSharedZoneKeys.insert(zone).inserted {
          output.yield(.collaborationAdded(zone))
        }
      }
      guard !changedZones.isEmpty else { return }

      let changes: CloudKitZoneChanges
      let zoneTokens = scope == .privateDatabase ? state.privateZoneTokens : state.zoneTokens
      do {
        changes = try await client.fetchRecordZoneChanges(
          scope: scope, zoneIDs: changedZones, tokens: zoneTokens)
      } catch let error as CKError where error.hasExpiredChangeToken {
        let expiredZones = error.expiredZoneIdentities.intersection(changedZones)
        let zonesToReset = expiredZones.isEmpty ? Set(changedZones) : expiredZones
        for zone in zonesToReset {
          switch scope {
          case .privateDatabase: state.privateZoneTokens.removeValue(forKey: zone)
          case .sharedDatabase: state.zoneTokens.removeValue(forKey: zone)
          }
        }
        let retryTokens = scope == .privateDatabase ? state.privateZoneTokens : state.zoneTokens
        changes = try await client.fetchRecordZoneChanges(
          scope: scope, zoneIDs: changedZones, tokens: retryTokens)
      }
      switch scope {
      case .privateDatabase: state.privateZoneTokens.merge(changes.tokens) { _, new in new }
      case .sharedDatabase: state.zoneTokens.merge(changes.tokens) { _, new in new }
      }
      if !changes.changedRecords.isEmpty { output.yield(.recordsChanged(changes.changedRecords)) }
      if !changes.deletedRecords.isEmpty { output.yield(.recordsDeleted(changes.deletedRecords)) }
    }
  }

  extension CKError {
    fileprivate var hasExpiredChangeToken: Bool {
      if code == .changeTokenExpired { return true }
      return partialErrorsByItemID?.values.contains {
        ($0 as? CKError)?.code == .changeTokenExpired
      } == true
    }

    fileprivate var expiredZoneIdentities: Set<CloudKitZoneIdentity> {
      Set(
        partialErrorsByItemID?.compactMap { key, value in
          guard (value as? CKError)?.code == .changeTokenExpired,
            let zoneID = key as? CKRecordZone.ID
          else { return nil }
          return CloudKitZoneIdentity(zoneID)
        } ?? [])
    }
  }

#endif
