#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

/// An actor providing low-level, Apple-like access to explicit zone-wide CloudKit sharing.
public actor CloudKitSharingStore {
    /// Compatibility alias for errors exposed by earlier releases.
    public typealias Error = CloudKitSharingError
    public let containerIdentifier: String
    public let databaseKind: CloudKitSharingDatabase
    private let client: any CloudKitClient
    private let retryPolicy: CloudKitRetryPolicy

    public init(containerIdentifier: String, database: CloudKitSharingDatabase) throws {
        try self.init(containerIdentifier: containerIdentifier, database: database, client: nil)
    }

    init(containerIdentifier: String, database: CloudKitSharingDatabase, client: (any CloudKitClient)?, retryPolicy: CloudKitRetryPolicy = .default) throws {
        guard !containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyContainerIdentifier }
        self.containerIdentifier = containerIdentifier; databaseKind = database
        self.client = client ?? SystemCloudKitClient(identifier: containerIdentifier, scope: database)
        self.retryPolicy = retryPolicy
    }

    public func accountStatus() async throws -> CKAccountStatus { try await perform("check account status") { try await client.accountStatus() } }

    public func validateReadiness() async -> CloudKitSharingReadiness {
        do {
            let status = try await accountStatus(); let issue: CloudKitSharingIssue? = switch status {
            case .available: nil
            case .noAccount: .noAccount
            case .restricted: .restrictedAccount
            case .temporarilyUnavailable: .temporarilyUnavailable
            case .couldNotDetermine: .couldNotDetermine
            @unknown default: .couldNotDetermine
            }
            var issues = issue.map { [$0] } ?? []
            if databaseKind != .privateDatabase { issues.append(.operationRequiresPrivateDatabase) }
            return .init(accountStatus: status, containerIdentifier: containerIdentifier, canCreateShares: issues.isEmpty, issues: issues)
        } catch {
            return .init(accountStatus: .couldNotDetermine, containerIdentifier: containerIdentifier, canCreateShares: false, issues: [.couldNotDetermine])
        }
    }

    @discardableResult public func createZone(named zoneName: String) async throws -> CKRecordZone.ID { try await fetchOrCreateZone(named: zoneName) }
    public func fetchZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone { try await perform("fetch zone") { try await client.zone(for: zoneID) } }
    public func fetchOrCreateZone(named zoneName: String) async throws -> CKRecordZone.ID {
        guard !zoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyZoneName }
        try requirePrivate()
        let id = CKRecordZone.ID(zoneName: zoneName)
        do { return try await client.zone(for: id).zoneID }
        catch let error as CKError where error.code == .unknownItem { return try await perform("create zone") { try await client.saveZone(.init(zoneName: zoneName)).zoneID } }
        catch { throw CloudKitSharingFailure(operation: "fetch or create zone", underlyingError: error) }
    }
    public func deleteZone(withID zoneID: CKRecordZone.ID) async throws { try requirePrivate(); try await perform("delete zone") { try await client.deleteZone(zoneID) } }
    @discardableResult public func save(_ record: CKRecord) async throws -> CKRecord { try await perform("save record") { try await client.saveRecord(record) } }
    public func record(for id: CKRecord.ID) async throws -> CKRecord { try await perform("fetch record") { try await client.record(for: id) } }
    public func records(ofType recordType: String, in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        guard !recordType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyRecordType }
        return try await perform("query \(recordType)") { try await client.records(ofType: recordType, zoneID: zoneID) }
    }
    public func records(ofType recordType: String, in collaboration: CloudKitCollaborationSummary) async throws -> [CKRecord] {
        guard collaboration.database == databaseKind, collaboration.containerIdentifier == containerIdentifier else {
            throw Error.containerMismatch(expected: containerIdentifier, actual: collaboration.containerIdentifier)
        }
        return try await records(ofType: recordType, in: collaboration.zoneID)
    }
    public func deleteRecord(withID id: CKRecord.ID) async throws { try await perform("delete record") { try await client.deleteRecord(id) } }

    public func createShare(for zoneID: CKRecordZone.ID, title: String? = nil) async throws -> CKShare { try await fetchOrCreateShare(for: zoneID, title: title) }
    public func fetchShare(for zoneID: CKRecordZone.ID) async throws -> CKShare {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await record(for: id) as? CKShare else { throw Error.shareWasNotSaved }
        return share
    }
    public func fetchOrCreateShare(for zoneID: CKRecordZone.ID, title: String?, thumbnailImageData: Data? = nil) async throws -> CKShare {
        try requirePrivate()
        do {
            let share = try await fetchShare(for: zoneID)
            guard share.url != nil else { throw Error.shareURLUnavailable }
            return share
        } catch let failure as CloudKitSharingFailure where (failure.underlyingError as? CKError)?.code == .unknownItem {
            let share = CKShare(recordZoneID: zoneID)
            return try await updateShare(share, title: title, thumbnailImageData: thumbnailImageData)
        }
    }
    public func updateShare(_ share: CKShare, title: String?, thumbnailImageData: Data? = nil) async throws -> CKShare {
        try requirePrivate()
        if let title, !title.isEmpty { share[CKShare.SystemFieldKey.title] = title as CKRecordValue }
        else { share[CKShare.SystemFieldKey.title] = nil }
        if let thumbnailImageData { share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData as CKRecordValue }
        else { share[CKShare.SystemFieldKey.thumbnailImageData] = nil }
        guard let saved = try await save(share) as? CKShare else { throw Error.shareWasNotSaved }
        guard saved.url != nil else { throw Error.shareURLUnavailable }
        return saved
    }
    public func stopSharing(zoneID: CKRecordZone.ID) async throws { try requirePrivate(); try await deleteRecord(withID: .init(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) }
    public func collaboration(for zoneID: CKRecordZone.ID) async throws -> CloudKitCollaboration {
        let share = try await fetchShare(for: zoneID); let user = share.currentUserParticipant
        return .init(id: zoneID, zoneID: zoneID, share: share, database: databaseKind, currentUserRole: user?.role, currentUserPermission: user?.permission, currentUserAcceptanceStatus: user?.acceptanceStatus)
    }
    public func participants(for zoneID: CKRecordZone.ID) async throws -> [CloudKitParticipantInfo] {
        let share = try await fetchShare(for: zoneID)
        return share.participants.map(participantInfo(from:))
    }
    public func owner(for zoneID: CKRecordZone.ID) async throws -> CloudKitParticipantInfo { participantInfo(from: try await fetchShare(for: zoneID).owner) }
    public func currentUserParticipant(for zoneID: CKRecordZone.ID) async throws -> CloudKitParticipantInfo? { try await fetchShare(for: zoneID).currentUserParticipant.map(participantInfo(from:)) }
    public func canCurrentUserEdit(zoneID: CKRecordZone.ID) async throws -> Bool { try await fetchShare(for: zoneID).currentUserParticipant?.permission == .readWrite }
    public func isCurrentUserOwner(zoneID: CKRecordZone.ID) async throws -> Bool { try await fetchShare(for: zoneID).currentUserParticipant?.role == .owner }

    public func accept(_ metadata: CKShare.Metadata) async throws -> AcceptedCloudKitShare {
        guard metadata.containerIdentifier == containerIdentifier else { throw Error.containerMismatch(expected: containerIdentifier, actual: metadata.containerIdentifier) }
        let recordID = metadata.share.recordID
        if metadata.participantStatus == .accepted { return .init(containerIdentifier: containerIdentifier, zoneID: recordID.zoneID, ownerName: recordID.zoneID.ownerName, shareRecordID: recordID) }
        _ = try await perform("accept invitation") { try await client.accept(metadata) }
        return .init(containerIdentifier: containerIdentifier, zoneID: recordID.zoneID, ownerName: recordID.zoneID.ownerName, shareRecordID: recordID)
    }
    public func sharedZones() async throws -> [CKRecordZone] { try await perform("discover shared zones") { try await client.allZones() } }
    public func collaborations() async throws -> [CloudKitCollaborationSummary] {
        guard databaseKind == .sharedDatabase else { return [] }
        return try await sharedZones().asyncCompactMap { zone in
            do { let share = try await fetchShare(for: zone.zoneID); return .init(containerIdentifier: containerIdentifier, database: databaseKind, zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, title: share[CKShare.SystemFieldKey.title] as? String) }
            catch let failure as CloudKitSharingFailure where (failure.underlyingError as? CKError)?.code == .unknownItem { return nil }
        }
    }

    public func subscriptions() async throws -> [CKSubscription] { try await perform("fetch subscriptions") { try await client.subscriptions() } }
    public func installSubscriptions() async throws {
        let id = subscriptionIdentifier
        if try await subscriptions().contains(where: { $0.subscriptionID == id }) { return }
        let subscription = CKDatabaseSubscription(subscriptionID: id); let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true; subscription.notificationInfo = info
        _ = try await perform("install subscription") { try await client.saveSubscription(subscription) }
    }
    public func removeSubscriptions() async throws {
        for subscription in try await subscriptions() where subscription.subscriptionID == subscriptionIdentifier { try await client.deleteSubscription(subscription.subscriptionID) }
    }
    private var subscriptionIdentifier: String { "com.ezswiftdata.sharing.\(containerIdentifier).\(databaseKind.rawValue)" }
    private func requirePrivate() throws { guard databaseKind == .privateDatabase else { throw Error.operationRequiresPrivateDatabase } }
    private func perform<T>(_ operation: String, action: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do { return try await action() } catch {
                attempt += 1
                guard attempt < retryPolicy.maximumAttempts, retryPolicy.isRetryable(error) else { throw CloudKitSharingFailure(operation: operation, underlyingError: error) }
                let requested = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? Double
                try await Task.sleep(for: requested.map(Duration.seconds) ?? .seconds(Double(attempt)))
            }
        }
    }
    private func participantInfo(from participant: CKShare.Participant) -> CloudKitParticipantInfo {
        let id = participant.userIdentity.userRecordID?.recordName ?? participant.userIdentity.lookupInfo?.emailAddress ?? UUID().uuidString
        let components = participant.userIdentity.nameComponents
        return .init(id: id, role: switch participant.role { case .owner: .owner; case .privateUser: .privateUser; case .publicUser: .publicUser; @unknown default: .unknown }, permission: switch participant.permission { case .none: .none; case .readOnly: .readOnly; case .readWrite: .readWrite; @unknown default: .unknown }, acceptanceStatus: switch participant.acceptanceStatus { case .unknown: .unknown; case .pending: .pending; case .accepted: .accepted; case .removed: .removed; @unknown default: .unknown }, displayName: components.map(PersonNameComponentsFormatter().string(from:)))
    }
}

private extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var result: [T] = []; for element in self { if let value = try await transform(element) { result.append(value) } }; return result
    }
}
#endif
