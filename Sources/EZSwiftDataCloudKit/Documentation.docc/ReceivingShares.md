# Receiving Shares

Forward the universal-link URL delivered to the app:

```swift
let shareURL = try CloudShareURL(url)
let invitation = try await cloud.invitation(from: shareURL)
let project = try await invitation.accept(as: Project.self)
```

CloudKit—not URL syntax—determines whether a share is expired, revoked, already
accepted, or available to the signed-in account. Batch acceptance returns one
`Result` per invitation so successful acceptances are never discarded by a partial failure.
