# Advanced CloudKit

Use ``CloudKitRecordRepresentable`` when records need native queryable fields,
`CKAsset`, `CKRecord.Reference`, parent relationships, or CloudKit encrypted values.
The default encoded payload is intentionally not queryable.

CloudKit encrypted fields cannot be queried or sorted. Participant email addresses
are not guaranteed because identity discoverability is controlled by CloudKit and
the user. CloudKit has no general ownership-transfer API, so this package does not
misrepresent permission changes as ownership transfer. Owners can stop sharing;
participants can leave through Apple's sharing UI.

`CKSyncEngine` requires application-specific state serialization and record-zone
ownership decisions. The package's incremental coordinator uses CloudKit server
change tokens and exposes sendable snapshots, allowing a SwiftData, Core Data, or
custom store to consume changes without sending non-Sendable records between actors.
