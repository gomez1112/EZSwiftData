import CloudKit
import EZSwiftData
import Observation
import SwiftData

@MainActor @Observable
final class SampleApplicationModel {
    enum Status: Equatable { case offline, idle, saving, sharing, synchronizing, retrying, failed(String) }
    let containerIdentifier = "iCloud.com.example.EZCloudSharingSample"
    private(set) var status: Status = .idle
    private(set) var share: CKShare?
    private(set) var collaborations: [CloudKitCollaborationSummary] = []
    let coordinator: CloudKitSharingCoordinator
    let router: CloudKitShareAcceptanceRouter

    init() throws {
        coordinator = try .init(containerIdentifier: containerIdentifier)
        router = .init(coordinator: coordinator)
    }
    func start() async { await run(status: .synchronizing) { try await coordinator.start(); try await reloadCollaborations() } }
    func prepareShare(for note: SharedNote) async {
        await run(status: .saving) {
            let store = try CloudKitSharingStore(containerIdentifier: containerIdentifier, database: .privateDatabase)
            let zoneID = try await store.fetchOrCreateZone(named: note.cloudZoneName)
            let recordID = CKRecord.ID(recordName: note.cloudRecordName, zoneID: zoneID)
            let snapshot = SharedNoteSnapshot(title: note.title, bodyText: note.bodyText, modifiedAt: note.modifiedAt)
            _ = try await store.save(SharedNoteRecord.makeRecord(from: snapshot, recordID: recordID))
            share = try await store.fetchOrCreateShare(for: zoneID, title: note.title)
            guard share?.url != nil else { throw CloudKitSharingError.shareURLUnavailable }
            status = .sharing
        }
    }
    func reloadCollaborations() async throws { collaborations = try await coordinator.collaborations() }
    func manualRefresh() async { await run(status: .synchronizing) { try await coordinator.synchronize(); try await reloadCollaborations() } }
    func becameActive() async { await coordinator.applicationBecameActive() }
    func processRemoteNotification(_ userInfo: [AnyHashable: Any]) async throws { _ = try await coordinator.processRemoteNotification(userInfo: userInfo) }
    func stopSharing(zoneID: CKRecordZone.ID) async {
        await run(status: .saving) { let store = try CloudKitSharingStore(containerIdentifier: containerIdentifier, database: .privateDatabase); try await store.stopSharing(zoneID: zoneID); share = nil }
    }
    private func run(status newStatus: Status, operation: () async throws -> Void) async {
        status = newStatus
        do { try await operation(); if status != .sharing { status = .idle } }
        catch { status = .failed(error.localizedDescription) }
    }
}
