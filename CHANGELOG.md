# Changelog

## Unreleased

- Added durable `FileCloudKitSyncStateStore` persistence and subscription lifecycle APIs.
- Restored the SwiftData bridge, share-acceptance router, and SwiftUI CloudKit sharing controller wrapper.
- Added conflict events, isolated database-scope failures, and coalesced follow-up synchronization for pushes received during a pass.
- **API change:** `CloudKitSharingStore.Error` is now a compatibility type alias for the richer `CloudKitSharingError`. Existing case-based source code continues to compile; code spelling the nested type may migrate to `CloudKitSharingError`.
- Lowered the deployment floor to the consistent iOS 18 generation: iOS 18, macOS 15, visionOS 2, and watchOS 11.
