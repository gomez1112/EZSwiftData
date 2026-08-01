#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

/// The CloudKit database used by an explicit sharing operation.
public enum CloudKitSharingDatabase: String, Codable, Sendable, CaseIterable {
    /// The owner's private database, where zones and shares are created.
    case privateDatabase
    /// The participant's shared database, where accepted zones are stored.
    case sharedDatabase
}

/// A stable, transferable representation of a CloudKit record identifier.
public struct CloudKitRecordIdentity: Codable, Hashable, Sendable {
    public let containerIdentifier: String
    public let database: CloudKitSharingDatabase
    public let zoneOwnerName: String
    public let zoneName: String
    public let recordName: String

    public init(containerIdentifier: String, database: CloudKitSharingDatabase, zoneOwnerName: String, zoneName: String, recordName: String) {
        self.containerIdentifier = containerIdentifier
        self.database = database
        self.zoneOwnerName = zoneOwnerName
        self.zoneName = zoneName
        self.recordName = recordName
    }
}

/// An immutable, Sendable record representation for synchronization and merging.
public struct CloudKitRecordSnapshot: Codable, Hashable, Sendable, Identifiable {
    public enum Value: Codable, Hashable, Sendable {
        case string(String), integer(Int64), double(Double), boolean(Bool), date(Date), data(Data)
    }
    public let identity: CloudKitRecordIdentity
    public let recordType: String
    public let fields: [String: Value]
    public let modificationDate: Date?
    public var id: CloudKitRecordIdentity { identity }

    public init(identity: CloudKitRecordIdentity, recordType: String, fields: [String: Value], modificationDate: Date? = nil) {
        self.identity = identity
        self.recordType = recordType
        self.fields = fields
        self.modificationDate = modificationDate
    }
}

/// Converts application-owned Sendable snapshots to and from CloudKit records.
public protocol CloudKitRecordConvertible {
    associatedtype Snapshot: Sendable
    static var recordType: String { get }
    static func makeRecord(from snapshot: Snapshot, recordID: CKRecord.ID) -> CKRecord
    static func snapshot(from record: CKRecord) throws -> Snapshot
}

/// Read-only information CloudKit exposes about a share participant.
public struct CloudKitParticipantInfo: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case owner, privateUser, publicUser, unknown }
    public enum Permission: String, Sendable { case none, readOnly, readWrite, unknown }
    public enum AcceptanceStatus: String, Sendable { case unknown, pending, accepted, removed }
    public let id: String
    public let role: Role
    public let permission: Permission
    public let acceptanceStatus: AcceptanceStatus
    public let displayName: String?
    public init(id: String, role: Role, permission: Permission, acceptanceStatus: AcceptanceStatus, displayName: String?) {
        self.id = id; self.role = role; self.permission = permission
        self.acceptanceStatus = acceptanceStatus; self.displayName = displayName
    }
}

/// Sendable collaboration metadata suitable for lists and persistence.
public struct CloudKitCollaborationSummary: Identifiable, Hashable, Sendable {
    public let containerIdentifier: String
    public let database: CloudKitSharingDatabase
    public let zoneName: String
    public let ownerName: String
    public let shareRecordName: String
    public let title: String?
    public var id: String { "\(database.rawValue)|\(ownerName)|\(zoneName)" }
    public var zoneID: CKRecordZone.ID { .init(zoneName: zoneName, ownerName: ownerName) }
    public var shareRecordID: CKRecord.ID { .init(recordName: shareRecordName, zoneID: zoneID) }

    public init(containerIdentifier: String, database: CloudKitSharingDatabase, zoneName: String, ownerName: String, shareRecordName: String = CKRecordNameZoneWideShare, title: String? = nil) {
        self.containerIdentifier = containerIdentifier; self.database = database
        self.zoneName = zoneName; self.ownerName = ownerName
        self.shareRecordName = shareRecordName; self.title = title
    }
}

/// Actor-isolated collaboration details. Access to the non-Sendable share remains on the actor returning it.
public struct CloudKitCollaboration: Identifiable {
    public let id: CKRecordZone.ID
    public let zoneID: CKRecordZone.ID
    public let share: CKShare
    public let database: CloudKitSharingDatabase
    public let currentUserRole: CKShare.ParticipantRole?
    public let currentUserPermission: CKShare.ParticipantPermission?
    public let currentUserAcceptanceStatus: CKShare.ParticipantAcceptanceStatus?
}

/// The result of accepting or recognizing an already accepted invitation.
public struct AcceptedCloudKitShare: Sendable {
    public let containerIdentifier: String
    public let zoneID: CKRecordZone.ID
    public let ownerName: String
    public let shareRecordID: CKRecord.ID
    public init(containerIdentifier: String, zoneID: CKRecordZone.ID, ownerName: String, shareRecordID: CKRecord.ID) {
        self.containerIdentifier = containerIdentifier; self.zoneID = zoneID
        self.ownerName = ownerName; self.shareRecordID = shareRecordID
    }
}

/// A configuration or account issue discovered before sharing.
public enum CloudKitSharingIssue: Hashable, Sendable {
    case noAccount, restrictedAccount, temporarilyUnavailable, couldNotDetermine
    case invalidContainerIdentifier, operationRequiresPrivateDatabase
}

/// Account and configuration diagnostics suitable for a preflight UI.
public struct CloudKitSharingReadiness: Sendable {
    public let accountStatus: CKAccountStatus
    public let containerIdentifier: String
    public let canCreateShares: Bool
    public let issues: [CloudKitSharingIssue]
}
#endif
