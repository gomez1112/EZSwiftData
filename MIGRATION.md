# CloudKit sharing migration

The original initializer, zone, record, query, delete, and `createShare` entry
points remain available. `createZone` and `createShare` are now idempotent.

The one source-breaking change is invitation acceptance: `accept(_:)` now returns
`AcceptedCloudKitShare` instead of `CKShare`. Code that ignored the old result is
source compatible; code that consumed it should use `shareRecordID` and `zoneID`
from the new value, then fetch the collaboration from a shared store.

Before adopting explicit sharing, change the relevant SwiftData configuration to
`cloudKitDatabase: .none`. Never allow SwiftData automatic CloudKit sync and this
explicit CKShare layer to own the same model graph.
