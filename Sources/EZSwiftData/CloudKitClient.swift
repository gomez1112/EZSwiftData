#if canImport(CloudKit)
@preconcurrency import CloudKit

protocol CloudKitClient: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone
    func zone(for id: CKRecordZone.ID) async throws -> CKRecordZone
    func allZones() async throws -> [CKRecordZone]
    func deleteZone(_ id: CKRecordZone.ID) async throws
    func saveRecord(_ record: CKRecord) async throws -> CKRecord
    func record(for id: CKRecord.ID) async throws -> CKRecord
    func deleteRecord(_ id: CKRecord.ID) async throws
    func records(ofType: String, zoneID: CKRecordZone.ID) async throws -> [CKRecord]
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare
    func subscriptions() async throws -> [CKSubscription]
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription
    func deleteSubscription(_ id: CKSubscription.ID) async throws
}

actor SystemCloudKitClient: CloudKitClient {
    private let container: CKContainer
    private let database: CKDatabase
    init(identifier: String, scope: CloudKitSharingDatabase) {
        container = CKContainer(identifier: identifier)
        database = scope == .privateDatabase ? container.privateCloudDatabase : container.sharedCloudDatabase
    }
    func accountStatus() async throws -> CKAccountStatus { try await container.accountStatus() }
    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone { try await database.save(zone) }
    func zone(for id: CKRecordZone.ID) async throws -> CKRecordZone { try await database.recordZone(for: id) }
    func allZones() async throws -> [CKRecordZone] { try await database.allRecordZones() }
    func deleteZone(_ id: CKRecordZone.ID) async throws { _ = try await database.deleteRecordZone(withID: id) }
    func saveRecord(_ record: CKRecord) async throws -> CKRecord { try await database.save(record) }
    func record(for id: CKRecord.ID) async throws -> CKRecord { try await database.record(for: id) }
    func deleteRecord(_ id: CKRecord.ID) async throws { _ = try await database.deleteRecord(withID: id) }
    func records(ofType type: String, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: .init(value: true))
        var output: [CKRecord] = []; var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: [(CKRecord.ID, Result<CKRecord, Error>)]; let next: CKQueryOperation.Cursor?
            if let cursor { (page, next) = try await database.records(continuingMatchFrom: cursor) }
            else { (page, next) = try await database.records(matching: query, inZoneWith: zoneID) }
            for (_, result) in page { output.append(try result.get()) }
            cursor = next
        } while cursor != nil
        return output
    }
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare { try await container.accept(metadata) }
    func subscriptions() async throws -> [CKSubscription] { try await database.allSubscriptions() }
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription { try await database.save(subscription) }
    func deleteSubscription(_ id: CKSubscription.ID) async throws { _ = try await database.deleteSubscription(withID: id) }
}
#endif
