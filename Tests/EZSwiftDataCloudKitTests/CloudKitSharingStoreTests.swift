#if canImport(CloudKit)
  import CloudKit
  import EZSwiftData
  import EZSwiftDataCloudKit
  import Foundation
  import SwiftData
  import XCTest

  @Model
  private final class CloudKitTestModel {
    var name: String

    init(name: String) {
      self.name = name
    }
  }

  final class CloudKitSharingStoreTests: XCTestCase {
    func testLegacySyncStateDecodingDefaultsPrivateZoneTokens() throws {
      let legacyState = """
        {
          "zoneTokens": [],
          "knownSharedZoneKeys": []
        }
        """

      let state = try JSONDecoder().decode(
        CloudKitSyncState.self,
        from: Data(legacyState.utf8)
      )

      XCTAssertTrue(state.zoneTokens.isEmpty)
      XCTAssertTrue(state.privateZoneTokens.isEmpty)
    }

    func testSyncStateRoundTripKeepsDatabaseZoneTokensSeparate() throws {
      let zone = CloudKitZoneIdentity(zoneName: "Collaboration", ownerName: "Owner")
      let sharedToken = CloudKitChangeToken(data: Data("shared".utf8))
      let privateToken = CloudKitChangeToken(data: Data("private".utf8))
      let state = CloudKitSyncState(
        zoneTokens: [zone: sharedToken],
        privateZoneTokens: [zone: privateToken]
      )

      let encoded = try JSONEncoder().encode(state)
      let decoded = try JSONDecoder().decode(CloudKitSyncState.self, from: encoded)

      XCTAssertEqual(decoded.zoneTokens[zone], sharedToken)
      XCTAssertEqual(decoded.privateZoneTokens[zone], privateToken)
    }

    func testEmptyContainerIdentifierIsRejected() {
      XCTAssertThrowsError(
        try CloudKitSharingStore(
          containerIdentifier: "",
          database: .privateDatabase
        )
      ) { error in
        XCTAssertEqual(
          error as? CloudKitSharingStore.Error,
          .emptyContainerIdentifier
        )
      }
    }

    @MainActor
    func testCloudKitClientCanUseCoreContainerFactory() throws {
      let container = try ModelContainerFactory.create(
        for: [CloudKitTestModel.self],
        isStoredInMemoryOnly: true
      )

      container.mainContext.insert(CloudKitTestModel(name: "Shared"))
      try container.mainContext.save()

      XCTAssertEqual(
        try container.mainContext.fetch(FetchDescriptor<CloudKitTestModel>()).count,
        1
      )
    }

    func testSynchronizationDeduplicatesChangedZonesAndSkipsDeletedZones() async throws {
      let liveZone = CloudKitZoneIdentity(zoneName: "Live", ownerName: "Owner")
      let deletedZone = CloudKitZoneIdentity(zoneName: "Deleted", ownerName: "Owner")
      let client = ZoneFilteringCloudKitClient(liveZone: liveZone, deletedZone: deletedZone)
      let stateStore = InMemoryCloudKitSyncStateStore()
      try await stateStore.save(
        CloudKitSyncState(knownSharedZoneKeys: [deletedZone]),
        containerIdentifier: "iCloud.tests"
      )
      let coordinator = CloudKitSharingCoordinator(
        containerIdentifier: "iCloud.tests",
        client: client,
        stateStore: stateStore
      )

      var addedZones: [CloudKitZoneIdentity] = []
      var removedZones: [CloudKitZoneIdentity] = []
      for await event in await coordinator.synchronize() {
        switch event {
        case let .collaborationAdded(zone): addedZones.append(zone)
        case let .collaborationRemoved(zone): removedZones.append(zone)
        default: break
        }
      }

      let requestedSharedZones = await client.requestedSharedZones()
      XCTAssertEqual(requestedSharedZones, [liveZone])
      XCTAssertEqual(addedZones, [liveZone])
      XCTAssertEqual(removedZones, [deletedZone])
    }
  }

  private actor ZoneFilteringCloudKitClient: CloudKitClient {
    let liveZone: CloudKitZoneIdentity
    let deletedZone: CloudKitZoneIdentity
    private var sharedZoneRequests: [[CloudKitZoneIdentity]] = []

    init(liveZone: CloudKitZoneIdentity, deletedZone: CloudKitZoneIdentity) {
      self.liveZone = liveZone
      self.deletedZone = deletedZone
    }

    func fetchDatabaseChanges(
      scope: CloudKitDatabaseScope,
      since token: CloudKitChangeToken?
    ) -> CloudKitDatabaseChanges {
      switch scope {
      case .privateDatabase:
        CloudKitDatabaseChanges(token: token, changedZoneIDs: [], deletedZoneIDs: [])
      case .sharedDatabase:
        CloudKitDatabaseChanges(
          token: token,
          changedZoneIDs: [liveZone, liveZone, deletedZone],
          deletedZoneIDs: [deletedZone]
        )
      }
    }

    func fetchRecordZoneChanges(
      scope: CloudKitDatabaseScope,
      zoneIDs: [CloudKitZoneIdentity],
      tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    ) -> CloudKitZoneChanges {
      if scope == .sharedDatabase {
        sharedZoneRequests.append(zoneIDs)
      }
      return CloudKitZoneChanges(tokens: [:], changedRecords: [], deletedRecords: [])
    }

    func save(
      records: [CloudKitRecordSnapshot],
      scope: CloudKitDatabaseScope
    ) -> [CloudKitBatchItemResult] {
      []
    }

    func delete(
      recordIDs: [CloudKitRecordIdentity],
      scope: CloudKitDatabaseScope
    ) -> [CloudKitBatchItemResult] {
      []
    }

    func requestedSharedZones() -> [CloudKitZoneIdentity] {
      sharedZoneRequests.flatMap(\.self)
    }
  }
#endif

#if canImport(CloudKit)
  private actor ScriptedCloudKitClient: CloudKitClient {
    var databaseChanges: [CloudKitDatabaseScope: CloudKitDatabaseChanges] = [:]
    var zoneChanges: [CloudKitDatabaseScope: CloudKitZoneChanges] = [:]
    var saveResults: [CloudKitBatchItemResult] = []
    private(set) var databaseTokens: [(CloudKitDatabaseScope, CloudKitChangeToken?)] = []

    func fetchDatabaseChanges(scope: CloudKitDatabaseScope, since token: CloudKitChangeToken?)
      throws -> CloudKitDatabaseChanges
    {
      databaseTokens.append((scope, token))
      return databaseChanges[scope] ?? .init(token: token, changedZoneIDs: [], deletedZoneIDs: [])
    }
    func fetchRecordZoneChanges(
      scope: CloudKitDatabaseScope, zoneIDs: [CloudKitZoneIdentity],
      tokens: [CloudKitZoneIdentity: CloudKitChangeToken]
    ) throws -> CloudKitZoneChanges {
      zoneChanges[scope] ?? .init(tokens: [:], changedRecords: [], deletedRecords: [])
    }
    func save(records: [CloudKitRecordSnapshot], scope: CloudKitDatabaseScope) throws
      -> [CloudKitBatchItemResult]
    { saveResults }
    func delete(recordIDs: [CloudKitRecordIdentity], scope: CloudKitDatabaseScope) throws
      -> [CloudKitBatchItemResult]
    { [] }
    func setDatabaseChanges(_ value: CloudKitDatabaseChanges, scope: CloudKitDatabaseScope) {
      databaseChanges[scope] = value
    }
    func setZoneChanges(_ value: CloudKitZoneChanges, scope: CloudKitDatabaseScope) {
      zoneChanges[scope] = value
    }
    func setSaveResults(_ value: [CloudKitBatchItemResult]) { saveResults = value }
    func receivedTokens() -> [(CloudKitDatabaseScope, CloudKitChangeToken?)] { databaseTokens }
  }

  extension CloudKitSharingStoreTests {
    func testFileStateStoreRoundTripAndCorruptionRecovery() async throws {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString, directoryHint: .isDirectory)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = FileCloudKitSyncStateStore(directory: directory)
      let expected = CloudKitSyncState(privateDatabaseToken: .init(data: Data("token".utf8)))
      try await store.save(expected, containerIdentifier: "iCloud/test:container")
      XCTAssertEqual(try await store.load(containerIdentifier: "iCloud/test:container"), expected)

      let url = await store.stateFileURL(containerIdentifier: "iCloud/test:container")
      try Data("not json".utf8).write(to: url, options: .atomic)
      XCTAssertEqual(try await store.load(containerIdentifier: "iCloud/test:container"), .init())
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path()))
    }

    func testFreshCoordinatorResumesFromFileToken() async throws {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString, directoryHint: .isDirectory)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = FileCloudKitSyncStateStore(directory: directory)
      let token = CloudKitChangeToken(data: Data("database".utf8))
      try await store.save(.init(privateDatabaseToken: token), containerIdentifier: "iCloud.tests")
      let client = ScriptedCloudKitClient()
      let coordinator = CloudKitSharingCoordinator(
        containerIdentifier: "iCloud.tests", client: client, stateStore: store)
      for await _ in await coordinator.synchronize() {}
      let received = await client.receivedTokens()
      XCTAssertEqual(received.first(where: { $0.0 == .privateDatabase })?.1, token)
    }

    func testScriptedChangesAndDeletionAreEmitted() async throws {
      let zone = CloudKitZoneIdentity(zoneName: "zone", ownerName: "owner")
      let identity = CloudKitRecordIdentity(recordName: "record", zone: zone)
      let snapshot = CloudKitRecordSnapshot(
        identity: identity, recordType: "Item", modificationDate: nil, encodedRecord: Data())
      let deletion = CloudKitRecordDeletion(identity: identity, recordType: "Item")
      let client = ScriptedCloudKitClient()
      await client.setDatabaseChanges(
        .init(token: nil, changedZoneIDs: [zone], deletedZoneIDs: []), scope: .sharedDatabase)
      await client.setZoneChanges(
        .init(tokens: [:], changedRecords: [snapshot], deletedRecords: [deletion]),
        scope: .sharedDatabase)
      let coordinator = CloudKitSharingCoordinator(
        containerIdentifier: "iCloud.tests", client: client,
        stateStore: InMemoryCloudKitSyncStateStore())
      var changed: [CloudKitRecordSnapshot] = []
      var deleted: [CloudKitRecordDeletion] = []
      for await event in await coordinator.synchronize() {
        if case let .recordsChanged(values) = event { changed += values }
        if case let .recordsDeleted(values) = event { deleted += values }
      }
      XCTAssertEqual(changed, [snapshot])
      XCTAssertEqual(deleted, [deletion])
    }

    func testConflictPoliciesAndConflictEvent() async throws {
      let zone = CloudKitZoneIdentity(zoneName: "zone", ownerName: "owner")
      let identity = CloudKitRecordIdentity(recordName: "record", zone: zone)
      let old = CloudKitRecordSnapshot(
        identity: identity, recordType: "Item", modificationDate: .distantPast,
        encodedRecord: Data("old".utf8))
      let new = CloudKitRecordSnapshot(
        identity: identity, recordType: "Item", modificationDate: .distantFuture,
        encodedRecord: Data("new".utf8))
      XCTAssertEqual(await CloudKitConflictPolicy.serverWins.resolve(client: old, server: new), new)
      XCTAssertEqual(await CloudKitConflictPolicy.clientWins.resolve(client: old, server: new), old)
      XCTAssertEqual(
        await CloudKitConflictPolicy.newestModificationDateWins.resolve(client: old, server: new),
        new)

      let client = ScriptedCloudKitClient()
      await client.setSaveResults([
        .init(
          identity: identity,
          result: .failure(
            .init(
              code: CKError.serverRecordChanged.rawValue, message: "conflict", clientRecord: old,
              serverRecord: new)))
      ])
      let coordinator = CloudKitSharingCoordinator(
        containerIdentifier: "iCloud.tests", client: client,
        stateStore: InMemoryCloudKitSyncStateStore())
      _ = await coordinator.save([old], scope: .privateDatabase)
      var iterator = coordinator.events.makeAsyncIterator()
      guard case let .conflict(clientSnapshot, serverSnapshot) = await iterator.next() else {
        return XCTFail("Expected conflict event")
      }
      XCTAssertEqual(clientSnapshot, old)
      XCTAssertEqual(serverSnapshot, new)
    }

    func testSubscriptionIdentifierMatchesNotificationContract() {
      XCTAssertEqual(
        CloudKitSharingStore.subscriptionIdentifier(
          containerIdentifier: "iCloud.tests", database: .sharedDatabase),
        "com.ezswiftdata.sharing.iCloud.tests.sharedDatabase"
      )
    }
  }
#endif
