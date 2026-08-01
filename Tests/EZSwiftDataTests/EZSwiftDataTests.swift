import Testing

#if canImport(CloudKit)
@preconcurrency import CloudKit
@testable import EZSwiftData

actor FakeCloudKitClient: CloudKitClient {
    var status: CKAccountStatus = .available
    var zones: [CKRecordZone.ID: CKRecordZone] = [:]
    var records: [CKRecord.ID: CKRecord] = [:]
    var installedSubscriptions: [CKSubscription] = []
    var saveZoneCalls = 0
    var saveSubscriptionCalls = 0
    var scriptedError: (any Error)?

    func accountStatus() async throws -> CKAccountStatus { if let scriptedError { throw scriptedError }; return status }
    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone { saveZoneCalls += 1; zones[zone.zoneID] = zone; return zone }
    func zone(for id: CKRecordZone.ID) async throws -> CKRecordZone {
        guard let zone = zones[id] else { throw CKError(.unknownItem) }; return zone
    }
    func allZones() async throws -> [CKRecordZone] { Array(zones.values) }
    func deleteZone(_ id: CKRecordZone.ID) async throws { zones[id] = nil }
    func saveRecord(_ record: CKRecord) async throws -> CKRecord { records[record.recordID] = record; return record }
    func record(for id: CKRecord.ID) async throws -> CKRecord { guard let record = records[id] else { throw CKError(.unknownItem) }; return record }
    func deleteRecord(_ id: CKRecord.ID) async throws { records[id] = nil }
    func records(ofType: String, zoneID: CKRecordZone.ID) async throws -> [CKRecord] { records.values.filter { $0.recordType == ofType && $0.recordID.zoneID == zoneID } }
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare { metadata.share }
    func subscriptions() async throws -> [CKSubscription] { installedSubscriptions }
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription { saveSubscriptionCalls += 1; installedSubscriptions.append(subscription); return subscription }
    func deleteSubscription(_ id: CKSubscription.ID) async throws { installedSubscriptions.removeAll { $0.subscriptionID == id } }
}

@Suite("CloudKitSharingStore deterministic behavior")
struct CloudKitSharingStoreTests {
    @Test("empty container identifier") func emptyContainer() {
        #expect(throws: CloudKitSharingError.emptyContainerIdentifier) { try CloudKitSharingStore(containerIdentifier: "", database: .privateDatabase) }
    }
    @Test("empty zone name") func emptyZone() async throws {
        let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: FakeCloudKitClient())
        await #expect(throws: CloudKitSharingError.emptyZoneName) { try await store.fetchOrCreateZone(named: "") }
    }
    @Test("empty record type") func emptyRecordType() async throws {
        let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: FakeCloudKitClient())
        await #expect(throws: CloudKitSharingError.emptyRecordType) { try await store.records(ofType: "", in: .init(zoneName: "z")) }
    }
    @Test("private-only operation rejects shared database") func privateOnly() async throws {
        let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .sharedDatabase, client: FakeCloudKitClient())
        await #expect(throws: CloudKitSharingError.operationRequiresPrivateDatabase) { try await store.fetchOrCreateZone(named: "z") }
    }
    @Test("fetch-or-create creates an absent zone once") func createsZone() async throws {
        let fake = FakeCloudKitClient(); let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: fake)
        _ = try await store.fetchOrCreateZone(named: "z"); _ = try await store.fetchOrCreateZone(named: "z")
        #expect(await fake.saveZoneCalls == 1)
    }
    @Test("share without server URL is rejected") func missingShareURL() async throws {
        let fake = FakeCloudKitClient(); let zone = CKRecordZone.ID(zoneName: "z")
        let share = CKShare(recordZoneID: zone); _ = try await fake.saveRecord(share)
        let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: fake)
        await #expect(throws: CloudKitSharingError.shareURLUnavailable) { try await store.fetchOrCreateShare(for: zone, title: nil) }
    }
    @Test("account unavailable appears in readiness") func accountUnavailable() async throws {
        let fake = FakeCloudKitClient(); await fake.setStatus(.noAccount)
        let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: fake)
        let readiness = await store.validateReadiness()
        #expect(!readiness.canCreateShares); #expect(readiness.issues == [.noAccount])
    }
    @Test("subscription installation is idempotent") func subscriptions() async throws {
        let fake = FakeCloudKitClient(); let store = try CloudKitSharingStore(containerIdentifier: "iCloud.test", database: .privateDatabase, client: fake)
        try await store.installSubscriptions(); try await store.installSubscriptions()
        #expect(await fake.saveSubscriptionCalls == 1)
    }
}

private extension FakeCloudKitClient {
    func setStatus(_ value: CKAccountStatus) { status = value }
}
#endif
