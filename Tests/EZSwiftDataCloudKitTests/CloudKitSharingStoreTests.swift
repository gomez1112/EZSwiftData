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
