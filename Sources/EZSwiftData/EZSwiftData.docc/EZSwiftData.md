# ``EZSwiftData``

Build a SwiftData local cache around explicit, zone-wide CloudKit collaboration.

## Architecture

```text
SwiftUI + @Observable application model
             |
CloudKitSharingCoordinator ---- AsyncStream<CloudKitSyncEvent>
       | private store | shared store
       | subscriptions | durable state
       v               v
       CKContainer / CKDatabase
             |
MainActor SwiftData merge delegate (local cache only)
```

Use ``CloudKitSharingStore`` directly for Apple-like control, add
``CloudKitSharingCoordinator`` for lifecycle and synchronization, and present
``EZCloudSharingView`` only where participant management is required.

## Topics

### Low-level sharing
- ``CloudKitSharingStore``
- ``CloudKitSharingDatabase``
- ``CloudKitCollaborationSummary``
- ``AcceptedCloudKitShare``

### Synchronization
- ``CloudKitSharingCoordinator``
- ``CloudKitSyncEvent``
- ``CloudKitConflictPolicy``
- ``CloudKitSyncStateStore``
- ``FileCloudKitSyncStateStore``

### Application integration
- ``CloudKitShareAcceptanceRouter``
- ``CloudKitSwiftDataMergeDelegate``
- ``CloudKitRecordConvertible``
- ``CloudKitSharingViewModel``
