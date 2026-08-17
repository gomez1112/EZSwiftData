//
//  CloudKitSharingStore.swift
//  EZSwiftDataCloudKit
//

#if canImport(CloudKit)
  import CloudKit

  /// The CloudKit database used by a ``CloudKitSharingStore``.
  public enum CloudKitSharingDatabase: Sendable {
    /// The owner's private database. Use this to create and manage shares.
    case privateDatabase

    /// The current user's shared database. Use this after accepting a share.
    case sharedDatabase
  }

  /// An actor that stores records in shareable CloudKit record zones.
  ///
  /// SwiftData's CloudKit configuration synchronizes an app's private store, but
  /// it does not expose `CKShare`. This type deliberately keeps shared CloudKit
  /// records separate from that store. Apps remain in control of translating
  /// between a SwiftData model and a `CKRecord`.
  ///
  /// Create one store for the owner's private database and another for the
  /// participant's shared database. All records in a collaboration belong in the
  /// same custom zone; sharing that zone lets CloudKit share the complete record
  /// graph and any records subsequently added to it.
  public actor CloudKitSharingStore {
    /// Compatibility alias; errors are now described by `CloudKitSharingError`.
    public typealias Error = CloudKitSharingError

    public let containerIdentifier: String
    public let databaseKind: CloudKitSharingDatabase

    private let container: CKContainer
    private let database: CKDatabase
    private let client: any CloudKitClient

    /// Creates a store backed by an app's CloudKit container.
    ///
    /// The container must be present in the consuming app's iCloud entitlement.
    /// A private store creates collaborations, while a shared store reads and
    /// writes collaborations accepted by the current user.
    public init(
      containerIdentifier: String,
      database: CloudKitSharingDatabase
    ) throws {
      guard !containerIdentifier.isEmpty else {
        throw Error.emptyContainerIdentifier
      }

      self.containerIdentifier = containerIdentifier
      self.databaseKind = database

      let container = CKContainer(identifier: containerIdentifier)
      self.container = container
      self.database =
        switch database {
        case .privateDatabase:
          container.privateCloudDatabase
        case .sharedDatabase:
          container.sharedCloudDatabase
        }
      self.client = LiveCloudKitClient(containerIdentifier: containerIdentifier)
    }

    /// The stable subscription identifier recognized by the synchronization coordinator.
    public nonisolated static func subscriptionIdentifier(
      containerIdentifier: String,
      database: CloudKitSharingDatabase
    ) -> String {
      "com.ezswiftdata.sharing.\(containerIdentifier).\(database.syncScope.rawValue)"
    }

    /// Installs the silent database subscription used for incremental push synchronization.
    /// Calling this method repeatedly is idempotent.
    @discardableResult
    public func installSubscriptions() async throws -> [CKSubscription] {
      let identifier = Self.subscriptionIdentifier(
        containerIdentifier: containerIdentifier,
        database: databaseKind
      )
      if let existing = try? await database.subscription(for: identifier) {
        return [existing]
      }
      let subscription = CKDatabaseSubscription(subscriptionID: identifier)
      let info = CKSubscription.NotificationInfo()
      info.shouldSendContentAvailable = true
      subscription.notificationInfo = info
      return [try await database.save(subscription)]
    }

    /// Returns subscriptions installed in this store's database.
    public func subscriptions() async throws -> [CKSubscription] {
      try await database.allSubscriptions()
    }

    /// Removes package-owned subscriptions while leaving unrelated app subscriptions intact.
    public func removeSubscriptions() async throws {
      let identifier = Self.subscriptionIdentifier(
        containerIdentifier: containerIdentifier,
        database: databaseKind
      )
      do {
        try await database.deleteSubscription(withID: identifier)
      } catch let error as CKError where error.code == .unknownItem {
        return
      }
    }

    /// Creates the custom record zone that represents one collaboration.
    ///
    /// Calling this again for an existing zone is safe: CloudKit returns the
    /// existing zone.
    @discardableResult
    public func createZone(named zoneName: String) async throws -> CKRecordZone.ID {
      guard !zoneName.isEmpty else {
        throw Error.emptyZoneName
      }
      guard case .privateDatabase = databaseKind else {
        throw Error.operationRequiresPrivateDatabase
      }

      let zone = CKRecordZone(zoneName: zoneName)
      let savedZone = try await database.save(zone)
      return savedZone.zoneID
    }

    /// Saves a record in this store's database.
    ///
    /// Construct new records with a `CKRecord.ID` whose `zoneID` is returned by
    /// ``createZone(named:)``. Relationships can be represented with
    /// `CKRecord.Reference` values in the same zone.
    @discardableResult
    public func save(_ record: CKRecord) async throws -> CKRecord {
      let results = try await save([record])
      guard let result = results.first else { throw Error.shareWasNotSaved }
      switch result.result {
      case let .success(snapshot):
        guard let snapshot else { throw Error.shareWasNotSaved }
        return try snapshot.record()
      case let .failure(error): throw error
      }
    }

    /// Saves records in CloudKit's maximum 400-item operation chunks. Each
    /// returned result belongs to one input record, so partial failures retain
    /// every successful save.
    public func save(_ records: [CKRecord]) async throws -> [CloudKitBatchItemResult] {
      let snapshots = try records.map(CloudKitRecordSnapshot.init)
      return try await client.save(records: snapshots, scope: databaseKind.syncScope)
    }

    /// Fetches one shared or private record by identifier.
    public func record(for id: CKRecord.ID) async throws -> CKRecord {
      try await database.record(for: id)
    }

    /// Fetches all records of a type from a collaboration zone.
    public func records(
      ofType recordType: String,
      in zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord] {
      guard !recordType.isEmpty else {
        throw Error.emptyRecordType
      }

      let query = CKQuery(recordType: recordType, predicate: .init(value: true))
      var records: [CKRecord] = []
      var cursor: CKQueryOperation.Cursor?

      repeat {
        let matchResults: [(CKRecord.ID, Result<CKRecord, Swift.Error>)]
        let nextCursor: CKQueryOperation.Cursor?

        if let cursor {
          (matchResults, nextCursor) = try await database.records(
            continuingMatchFrom: cursor
          )
        } else {
          (matchResults, nextCursor) = try await database.records(
            matching: query,
            inZoneWith: zoneID
          )
        }

        for (_, result) in matchResults {
          records.append(try result.get())
        }
        cursor = nextCursor
      } while cursor != nil

      return records
    }

    /// Deletes a record from a collaboration zone.
    public func deleteRecord(withID id: CKRecord.ID) async throws {
      let results = try await deleteRecords(withIDs: [id])
      guard let result = results.first else {
        throw CloudKitSynchronizationError.missingOperationResult
      }
      if case let .failure(error) = result.result { throw error }
    }

    /// Deletes records in 400-item chunks and reports partial failures by item.
    public func deleteRecords(withIDs ids: [CKRecord.ID]) async throws -> [CloudKitBatchItemResult]
    {
      try await client.delete(
        recordIDs: ids.map(CloudKitRecordIdentity.init), scope: databaseKind.syncScope)
    }

    /// Creates and saves a share for an entire collaboration zone.
    ///
    /// Present the returned value with SwiftUI's `CloudSharingView`, using a
    /// `CKContainer` initialized with ``containerIdentifier``. New records saved
    /// into the zone are automatically part of the collaboration.
    public func createShare(
      for zoneID: CKRecordZone.ID,
      title: String? = nil
    ) async throws -> CKShare {
      guard case .privateDatabase = databaseKind else {
        throw Error.operationRequiresPrivateDatabase
      }

      let share = CKShare(recordZoneID: zoneID)
      if let title, !title.isEmpty {
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
      }

      let savedRecord = try await database.save(share)
      guard let savedShare = savedRecord as? CKShare else {
        throw Error.shareWasNotSaved
      }
      return savedShare
    }

    /// Accepts an invitation delivered to the app by CloudKit.
    ///
    /// After acceptance, use a store configured with ``CloudKitSharingDatabase/sharedDatabase``
    /// and the zone ID in the metadata to read the collaboration.
    @discardableResult
    public func accept(_ metadata: CKShare.Metadata) async throws -> CKShare {
      try await container.accept(metadata)
    }
  }

  extension CloudKitSharingDatabase {
    fileprivate var syncScope: CloudKitDatabaseScope {
      switch self {
      case .privateDatabase: .privateDatabase
      case .sharedDatabase: .sharedDatabase
      }
    }
  }
#endif
