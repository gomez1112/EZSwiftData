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
}
#endif
