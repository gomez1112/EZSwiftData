#if canImport(CloudKit)
import CloudKit
import EZSwiftData
import EZSwiftDataCloudKit
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
