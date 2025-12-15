# EZSwiftData

Small, pragmatic helpers for **SwiftData** that make it easier to:

- Create `ModelContainer`s for **production**, **previews**, and **tests**
- Build **seeded SwiftUI previews** using the `#Preview` macro
- Inject **unlimited preview-only dependencies** *without* `AnyView`
- Add tiny **ModelContext insert helpers** for cleaner sample data seeding

> **Philosophy:** minimal surface area, Apple-like APIs, and “progressive disclosure”: the simple path stays simple, and power features only appear when you need them.

---

## Requirements

- Swift tools: **Swift 6.2**
- Platforms:
  - iOS **18+**
  - macOS **15+**
  - visionOS **2+**

(These match the package manifest.)

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
let container = ModelContainerFactory.create(
    TestPet.self,
    TestOwner.self
)
```

Or with an explicit array:

```swift
@MainActor
let container = ModelContainerFactory.create(
    for: [TestPet.self, TestOwner.self],
    isStoredInMemoryOnly: true
)
```

#### Use in your `App`

```swift
import SwiftUI
import SwiftData
import EZSwiftData

@main
struct MyApp: App {
    @MainActor
    private let container = ModelContainerFactory.create(
        MyModelA.self,
        MyModelB.self
    )

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

### 2) Seeded SwiftUI previews (no boilerplate)

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
    static func seed(_ context: ModelContext) {
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
2. Seeds it with `AppPreviewConfig.seed(_:)`
3. Injects it via `.modelContainer(...)`

**B. Seeded preview + custom dependencies (no `AnyView`)**

If you want to also inject preview-only environment values (feature flags, mock services, etc.), use `.dev(...)`.

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

### 3) `ModelContext` insert helpers

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
    @MainActor static func seed(_ context: ModelContext)
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
- `ModelContext.insert(...)` helpers for seeding
- `DataPreviewer.makeSharedContext()` for validating preview context creation

Example in-memory setup:

```swift
@MainActor
func makeTestContainer() -> ModelContainer {
    ModelContainerFactory.create(
        for: [Pet.self, Owner.self],
        isStoredInMemoryOnly: true
    )
}
```

> If you ever want to test the `fatalError` path, you’ll need an injectable error handler or a small test hook. The package intentionally keeps the production factory tiny.

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
ModelContainerFactory.create(for:isStoredInMemoryOnly:)
```

Keeping it explicit avoids encouraging test-only patterns in production call sites.

### Why a `ViewModifier` closure for preview dependencies?
It guarantees:
- concrete types (no `AnyView`)
- composability (stack multiple `.environment(...)` calls)
- zero arity limits (one closure can build anything)

---

## Package Layout

- **ModelContainerFactory**: production + in-memory container creation
- **SwiftDataPreviewContextConfig**: per-app preview definition (models + seed)
- **DataPreviewer**: generic preview modifier that wires everything together
- **PreviewTrait extensions**: `.seeded(...)` and `.dev(...)` convenience traits
- **ModelContext extension**: `insert(...)` helpers for sequences + variadics

---

## License

MIT (or your preferred license). Add a `LICENSE` file to your repository to make it explicit.

