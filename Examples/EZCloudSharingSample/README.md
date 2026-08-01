# EZCloudSharingSample

Create an iOS 27 app target named **EZCloudSharingSample**, add EZSwiftData as a
local package, include the Swift files in this directory, and replace the sample
container identifier. Enable iCloud/CloudKit, Background Modes > Remote
notifications, and the `aps-environment` entitlement. The app intentionally uses
SwiftData only as a local cache; CloudKit is the collaboration source of truth.

`SceneDelegate.forward(metadata:to:)` shows both cold-launch (connection options)
and warm-launch (`userDidAcceptCloudKitShareWith`) forwarding. The app delegate
shows remote-notification forwarding. Production apps should retain their router
in application state rather than creating one per callback.
