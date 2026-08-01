# EZSwiftData

Small, pragmatic helpers for **SwiftData** that make it easier to:

- Create `ModelContainer`s for **production**, **previews**, and **tests**
- Create `ModelContainer`s that support **SwiftData migrations**
- Create **seeded containers in one call** for previews or tests
- Build **seeded SwiftUI previews** using the `#Preview` macro
- Inject **unlimited preview-only dependencies** *without* `AnyView`
- Add tiny **ModelContext insert helpers** for cleaner sample data seeding
- Share CloudKit record zones with other iCloud users

> **Philosophy:** minimal surface area, Apple-like APIs, and “progressive disclosure”: the simple path stays simple, and power features only appear when you need them.

---

## Requirements

- Swift tools: **Swift 6.3** with strict concurrency
- Platforms:
  - iOS / iPadOS **27+**
  - macOS **27+**
  - visionOS **2+**

(These match the package manifest.)

---

## Sharing records with other iCloud users

`CloudKitSharingStore` adds Apple-native collaboration without adding a third-party dependency. SwiftData's CloudKit-backed `ModelConfiguration` synchronizes a user's private data, but does not expose `CKShare`; shared records therefore live in a dedicated CloudKit record zone. Your app explicitly translates between its SwiftData models and `CKRecord` values, which keeps local persistence and collaboration boundaries clear.

> **One source of truth:** records managed by EZSwiftData's explicit sharing layer
> must not also be managed by SwiftData automatic CloudKit synchronization. Use
> SwiftData as a local cache:
>
> ```swift
> let configuration = ModelConfiguration(
>     "LocalCache",
>     schema: schema,
>     cloudKitDatabase: .none
> )
> ```

Before using this API, enable **iCloud → CloudKit** for the consuming app target, add the container to its entitlements, and deploy the record types used below in CloudKit Console.

### Create and present a collaboration

```swift
import CloudKit
import EZSwiftData
import SwiftUI

let containerIdentifier = "iCloud.com.example.MyApp"
let ownerStore = try CloudKitSharingStore(
    containerIdentifier: containerIdentifier,
    database: .privateDatabase
)

let zoneID = try await ownerStore.fetchOrCreateZone(named: UUID().uuidString)
let recordID = CKRecord.ID(recordName: model.cloudID, zoneID: zoneID)
let record = CKRecord(recordType: "SharedItem", recordID: recordID)
record["title"] = model.title as CKRecordValue
try await ownerStore.save(record)

let share = try await ownerStore.fetchOrCreateShare(for: zoneID, title: model.title)
guard share.url != nil else { throw CloudKitSharingError.shareURLUnavailable }
```

Present the server-saved share using the native system UI. It handles invitations,
Messages and Mail destinations, participant permissions/removal, and stopping a share:

```swift
EZCloudSharingView(
    share: share,
    containerIdentifier: containerIdentifier,
    availablePermissions: [.allowPrivate, .allowReadOnly, .allowReadWrite]
)
```

### Accept and load a collaboration

Forward the `CKShare.Metadata` delivered to your app to the owner store (or another store for the same container), then query the shared database using the invitation's zone ID:

```swift
let accepted = try await ownerStore.accept(metadata)

let participantStore = try CloudKitSharingStore(
    containerIdentifier: containerIdentifier,
    database: .sharedDatabase
)
let records = try await participantStore.records(
    ofType: "SharedItem",
    in: accepted.zoneID
)
```

Merge the returned values into SwiftData on the main actor. Persist a stable CloudKit record name (for example, a UUID string) on each shared SwiftData model so subsequent saves update the same CloudKit record rather than creating duplicates.

### Coordinator, invitations, and refresh

```swift
let coordinator = try CloudKitSharingCoordinator(
    containerIdentifier: containerIdentifier,
    configuration: .init(conflictPolicy: .newestModificationDateWins)
)
try await coordinator.start() // starting twice is safe

for await event in coordinator.events {
    // Convert Sendable snapshots and merge into SwiftData on MainActor.
}
```

An SPM package cannot install lifecycle delegates in its consuming app. Retain a
`CloudKitShareAcceptanceRouter`, forward cold-launch metadata from
`UIScene.ConnectionOptions.cloudKitShareMetadata`, and forward warm-launch metadata
from `windowScene(_:userDidAcceptCloudKitShareWith:)` to `await router.handle(metadata)`.
See `Examples/EZCloudSharingSample/SceneDelegate.swift` for exact code.

Forward CloudKit pushes from the app delegate's modern async
`application(_:didReceiveRemoteNotification:)` callback to
`processRemoteNotification(userInfo:)`. Enable **Signing & Capabilities → Background
Modes → Remote notifications** and the correct APNs environment. Silent pushes are
opportunistic, not immediate or guaranteed. Also call `applicationBecameActive()`
when SwiftUI's `scenePhase` becomes active, and provide `.refreshable` for explicit
repair. This push + foreground + manual strategy avoids continuous polling.

### Entitlements and CloudKit schema

Enable iCloud Drive and CloudKit, select the exact container in the app entitlement,
and use the same bundle identity/container entitlement on both devices. Development
builds normally use CloudKit's **Development** environment; Production is a separate
schema. `records(ofType:in:)` uses `CKQuery`. If CloudKit reports that `recordName`
is not queryable, open CloudKit Console, choose the correct container and environment,
select the application's record type, and add a **QUERYABLE** index for `recordName`.

### Device validation and diagnostics

- Test complete invitations on two physical devices using two different Apple IDs.
- Both devices need iCloud Drive. Do not invite the owner's own Apple ID.
- Messages may be absent from the simulator share sheet, and participant resolution
  may fail there. These are simulator testing limitations, not a guaranteed platform bug.
- “Couldn't Add People” can require a physical device and a server-saved share.
  Always validate `share.url` before presentation.
- Account preflight is available through `validateReadiness()`; presentation-ready
  failures distinguish authentication, permission, quota, networking, throttling,
  partial failures, schema indexes, and container mismatches.

### Conflict and deletion semantics

The coordinator defaults to `serverWins`, with `clientWins`, newest-modification-date,
and async custom policies available. Remote deletions are emitted as tombstones.
EZSwiftData never silently deletes local user-created SwiftData objects: the app's
main-actor merge delegate decides how tombstones affect its cache. Stopping a zone-wide
share deletes the share record, never the zone or its owner records.

### Past schema failures to avoid

1. CloudKit-backed SwiftData requires declaration-site defaults for nonoptional properties.
2. SwiftData CloudKit integration does not support unique constraints.
3. Never put `@Attribute(.unique)` on a cached CloudKit identity.
4. Never enable automatic SwiftData CloudKit sync for the same explicitly shared graph.
5. Delete an old development app/store after incompatible local schema changes.
6. Messages may not appear in the simulator.
7. “Couldn't Add People” needs validation with a server-saved share on real devices.
8. Validate that `share.url` is nonnil.
9. Participant queries fail if the record type's `recordName` is not QUERYABLE.
10. Add that index in the same Development or Production environment used by the build.

### Limitations

CloudKit requires entitlements, deployed schema, APNs, iCloud accounts, and physical
devices for end-to-end validation; deterministic package tests therefore use fakes
and never contact CloudKit. System participant UI controls which destinations are
available. Delivery timing remains controlled by CloudKit/APNs. See
`Examples/EZCloudSharingSample` for owner, participant, acceptance, foreground,
notification, deletion, permission-error, offline, and retry integration points.

---

## Installation

### Swift Package Manager (Xcode)

1. In Xcode: **File → Add Package Dependencies…**
2. Paste your repository URL
3. Add **EZSwiftData** to your app target

Then import:

```swift
import EZSwiftData
import SwiftData
```

---

## What’s Included

### 1) `ModelContainerFactory`

A tiny factory that creates a `ModelContainer` for a given set of model types.

- **Production:** `isStoredInMemoryOnly: false` (default)
- **Previews/Tests:** `isStoredInMemoryOnly: true`

```swift
import EZSwiftData
import SwiftData

@MainActor
let container = try ModelContainerFactory.create(
    TestPet.self,
    TestOwner.self
)
```

Or with an explicit array:

```swift
@MainActor
let container = try ModelContainerFactory.create(
    for: [TestPet.self, TestOwner.self],
    isStoredInMemoryOnly: true
)
```

#### Migration-aware containers

If your app uses `VersionedSchema` and `SchemaMigrationPlan`, EZSwiftData can create the container with the migration plan attached:

```swift
import EZSwiftData
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Pet.self
    ]
}

enum AppSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Pet.self,
        Owner.self
    ]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        AppSchemaV1.self,
        AppSchemaV2.self
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)
    ]
}

@MainActor
let container = try ModelContainerFactory.create(
    migrationPlan: AppMigrationPlan.self
)
```

This uses the explicit convenience API:

```swift
ModelContainerFactory.create(migrationPlan: AppMigrationPlan.self)
```

You can also provide the current schema explicitly:

```swift
@MainActor
let container = try ModelContainerFactory.create(
    for: AppSchemaV2.self,
    migrationPlan: AppMigrationPlan.self
)
```

When using `create(migrationPlan:)`, EZSwiftData loads the last schema listed in `AppMigrationPlan.schemas` as the current schema and passes the migration plan through to SwiftData.

#### Use in your `App`

```swift
import SwiftUI
import SwiftData
import EZSwiftData

@main
struct MyApp: App {
    private let container: ModelContainer

    @MainActor
    init() {
        do {
            container = try ModelContainerFactory.create(
                MyModelA.self,
                MyModelB.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
```

> `create(...)` is `@MainActor`, which keeps SwiftData setup and context usage on the correct actor.

---

### 2) One-line seeded containers (✨ great for previews & tests)

Need a container and data immediately? Use `createSeeded(...)`:

```swift
import SwiftData
import EZSwiftData

@MainActor
let container = try ModelContainerFactory.createSeeded(
    for: [Pet.self, Owner.self],
    isStoredInMemoryOnly: true
) { context in
    context.insert(Pet(name: "Mango"))
    context.insert(Owner(name: "Gerard"))
}
```

This keeps setup compact while ensuring seeding runs on the `MainActor`. The
factory saves the context before returning, so the container does not depend on
autosave to persist its seed data.

If your seed workflow needs async work, use the async overload:

```swift
@MainActor
let container = try await ModelContainerFactory.createSeeded(
    for: [Pet.self],
    isStoredInMemoryOnly: true
) { context in
    context.insert(Pet(name: "Mango"))
    // e.g. await network/client setup before final seed inserts
}
```


---

### 3) Seeded SwiftUI previews (no boilerplate)

EZSwiftData lets you define a **per-app preview config** describing:

- which models your preview uses
- how to insert your sample data

#### Step 1 — Create a preview config

```swift
import SwiftData
import EZSwiftData

enum AppPreviewConfig: SwiftDataPreviewContextConfig {
    static let models: [any PersistentModel.Type] = [
        Pet.self,
        Owner.self
    ]

    @MainActor
    static func seed(_ context: ModelContext) throws {
        context.insert(Pet(name: "Mango"))
        context.insert(Pet(name: "Kiwi"))
        context.insert(Owner(name: "Gerard"))
    }
}
```

#### Step 2 — Use it in `#Preview`

**A. Simple seeded preview**

```swift
import SwiftUI
import EZSwiftData

#Preview("Seeded", traits: .seeded(AppPreviewConfig.self)) {
    ContentView()
}
```

This path:
1. Builds an **in-memory** SwiftData container from `AppPreviewConfig.models`
2. Seeds and saves it with `AppPreviewConfig.seed(_:)`
3. Injects it via `.modelContainer(...)`

**B. Seeded preview + custom dependencies (no `AnyView`)**

If you want to also inject preview-only environment values (feature flags, mock services, etc.), use `.dev(...)`.

You can also start with `.dev(AppPreviewConfig.self)` and add dependencies later.

```swift
import SwiftUI
import SwiftData
import EZSwiftData

struct PreviewDependencies: ViewModifier {
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            // Example: Inject anything you need for previews.
            // .environment(\.myFeatureFlags, .preview)
            // .environment(MyService.self, .mock)
    }
}

// Cleaner call-site (unlabeled closure)
#Preview("Dev", traits: .dev(AppPreviewConfig.self) { context in
    PreviewDependencies(context: context)
}) {
    ContentView()
}
```

**Why this design?**
- You get **infinite dependencies** by composing a single concrete `ViewModifier`
- No `AnyView`
- No “arity-limited” overloads (no `.withA(...).withB(...)` ladders)

---

### 4) `ModelContext` insert helpers

Seeding sample data is usually a lot of `insert(...)` calls. These helpers make it cleaner:

```swift
import SwiftData
import EZSwiftData

@MainActor
func seed(_ context: ModelContext) {
    // Sequence
    context.insert([Pet(name: "A"), Pet(name: "B")])

    // Variadic
    context.insert(
        Pet(name: "C"),
        Pet(name: "D")
    )
}
```

---

## How it Works (High Level)

### `SwiftDataPreviewContextConfig`

Your app defines:

- `static var models: [any PersistentModel.Type]`
- `static func seed(_ context: ModelContext)`

```swift
public protocol SwiftDataPreviewContextConfig {
    static var models: [any PersistentModel.Type] { get }
    @MainActor static func seed(_ context: ModelContext) throws
}
```

### `DataPreviewer`

A generic `PreviewModifier` that:

1) Creates an in-memory container (via `ModelContainerFactory`)  
2) Seeds it (via `Config.seed`)  
3) Applies your concrete `ViewModifier` (if any)  
4) Injects the container using `.modelContainer(context)`

This pattern makes previews deterministic and keeps model access on the right actor.

---

## Testing

EZSwiftData is designed so you can write tests that exercise the **public surface**:

- `ModelContainerFactory.create(...)` for container creation
- `ModelContainerFactory.create(migrationPlan:...)` for migration-aware container creation
- `ModelContext.insert(...)` helpers for seeding
- `DataPreviewer.makeSharedContext()` for validating preview context creation

Example in-memory setup:

```swift
@MainActor
func makeTestContainer() throws -> ModelContainer {
    try ModelContainerFactory.create(
        for: [Pet.self, Owner.self],
        isStoredInMemoryOnly: true
    )
}
```

> Errors are thrown as `ModelContainerFactory.Error` so you can assert failure paths without a `fatalError` hook.

---

## Concurrency & Actor Isolation Notes

- `ModelContainerFactory.create(...)` is `@MainActor` to keep SwiftData setup aligned with UI usage.
- `DataPreviewer.makeSharedContext()` is `nonisolated` + async (required by `PreviewModifier`), but it seeds on the `MainActor`:
  - container creation is done via `ModelContainerFactory`
  - seeding runs inside `MainActor.run { ... }`

If you see actor isolation warnings in your app preview code, ensure your seed logic is marked `@MainActor`.

---

## Progressive Disclosure

You can adopt EZSwiftData in stages:

1. **Just use `ModelContainerFactory`** for clean production + test containers
2. Add **`SwiftDataPreviewContextConfig`** for seeded previews
3. Use **`.dev(...)`** only when you need preview-only dependency injection

---

## FAQ

### Why not ship a public “test container” API?
You already get it with:

```swift
try ModelContainerFactory.create(for:isStoredInMemoryOnly:)
```

Keeping it explicit avoids encouraging test-only patterns in production call sites.

### Why a `ViewModifier` closure for preview dependencies?
It guarantees:
- concrete types (no `AnyView`)
- composability (stack multiple `.environment(...)` calls)
- zero arity limits (one closure can build anything)

---

## Package Layout

- **ModelContainerFactory**: production + in-memory container creation, plus `createSeeded(...)` for one-line seeding
- **SwiftDataPreviewContextConfig**: per-app preview definition (models + seed)
- **DataPreviewer**: generic preview modifier that wires everything together
- **PreviewTrait extensions**: `.seeded(...)` and `.dev(...)` convenience traits
- **ModelContext extension**: `insert(...)` helpers for sequences + variadics
