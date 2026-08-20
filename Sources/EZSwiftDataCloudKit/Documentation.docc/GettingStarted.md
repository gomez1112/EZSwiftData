# Getting Started

Enable iCloud and CloudKit for the application target, select its CloudKit container,
and deploy development schema to production in CloudKit Console before shipping.
The package itself cannot add an application's entitlements.

Use ``Cloud/default`` when the target's default container is the intended container:

```swift
let cloud = Cloud.default
```

This uses `CKContainer.default()`, so the iCloud capability and entitlements selected
in Xcode remain the source of truth, as they are for SwiftData's default CloudKit
configuration. Create a ``Cloud`` with an explicit
``CloudConfiguration/containerIdentifier`` only to select a non-default container.
The lower-level synchronization and ``CloudKitSharingStore`` APIs require an explicit
identifier because it also identifies subscriptions and persisted sync state.

Create a `Codable`, `Identifiable`, and `Sendable` value conforming to
``CloudShareable``. Then call ``Cloud/share(_:options:)``. A share uses a custom
record zone so records later added to that zone join the same collaboration.

Present the resulting `CKShare` using Apple's system sharing UI. Never print or
persist the share URL in logs.
