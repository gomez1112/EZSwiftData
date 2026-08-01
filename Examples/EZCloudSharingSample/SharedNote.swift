import CloudKit
import EZSwiftData
import SwiftData

@Model
final class SharedNote {
    // Defaults are required for CloudKit-compatible schema evolution. This local
    // cache deliberately has no @Attribute(.unique) constraint.
    var cloudRecordName: String = ""
    var cloudZoneName: String = ""
    var cloudZoneOwnerName: String = CKCurrentUserDefaultName
    var cloudDatabaseScope: String = CloudKitSharingDatabase.privateDatabase.rawValue
    var title: String = ""
    var bodyText: String = ""
    var modifiedAt: Date = .now

    init(title: String = "", bodyText: String = "") {
        cloudRecordName = UUID().uuidString; cloudZoneName = UUID().uuidString
        self.title = title; self.bodyText = bodyText
    }
}

struct SharedNoteSnapshot: Codable, Sendable {
    let title: String
    let bodyText: String
    let modifiedAt: Date
}

enum SharedNoteRecord: CloudKitRecordConvertible {
    static let recordType = "SharedNote"
    static func makeRecord(from snapshot: SharedNoteSnapshot, recordID: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["title"] = snapshot.title as CKRecordValue
        record["bodyText"] = snapshot.bodyText as CKRecordValue
        record["modifiedAt"] = snapshot.modifiedAt as CKRecordValue
        return record
    }
    static func snapshot(from record: CKRecord) throws -> SharedNoteSnapshot {
        .init(title: record["title"] as? String ?? "", bodyText: record["bodyText"] as? String ?? "", modifiedAt: record["modifiedAt"] as? Date ?? .distantPast)
    }
}
