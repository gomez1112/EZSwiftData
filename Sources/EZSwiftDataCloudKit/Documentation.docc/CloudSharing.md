# ``EZSwiftDataCloudKit``

Make CloudKit collaboration feel native to Swift without hiding CloudKit when you need it.

## Overview

Start with a normal value:

```swift
struct Project: CloudShareable {
  let id: UUID
  var name: String
}

let cloud = Cloud(configuration: .init(
  containerIdentifier: "iCloud.com.example.app"
))
let share = try await cloud.share(Project(id: UUID(), name: "Garden"))
```

The default mapping stores a versioned Codable payload. Adopt
``CloudKitRecordRepresentable`` only when a property must be a queryable CloudKit
field, an encrypted value, an asset, or a reference.

### Topics

- <doc:GettingStarted>
- <doc:ReceivingShares>
- <doc:AdvancedCloudKit>
