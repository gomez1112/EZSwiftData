# Getting Started

Enable iCloud and CloudKit for the application target, select its CloudKit container,
and deploy development schema to production in CloudKit Console before shipping.
The package itself cannot add an application's entitlements.

Create a `Codable`, `Identifiable`, and `Sendable` value conforming to
``CloudShareable``. Then call ``Cloud/share(_:options:)``. A share uses a custom
record zone so records later added to that zone join the same collaboration.

Present the resulting `CKShare` using Apple's system sharing UI. Never print or
persist the share URL in logs.
