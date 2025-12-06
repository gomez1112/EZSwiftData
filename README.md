# EZSwiftData

A tiny Swift package that removes repeated SwiftData boilerplate for **production containers** and **preview seeding**, while keeping dependency injection **fully type-safe** and **AnyView-free**.

This package is designed for apps that:
- use SwiftData with multiple models
- seed sample data in previews
- want to inject any number of preview-only dependencies cleanly
- prefer small, honest abstractions over complex “magic”

---

## Features

- ✅ Simple production container factory
- ✅ Preview support with in-memory containers
- ✅ Easy sample data seeding
- ✅ Type-safe preview dependency injection via your own `ViewModifier`
- ✅ No `AnyView`
- ✅ No arity-limited environment APIs
- ✅ Minimal per-app setup
- ✅ Test suite included

---

## Installation

Add the package in Xcode:

**File → Add Packages…**

Then import:

```swift
import SwiftDataPreviewer
```

---

## 1) Production usage

```swift
import SwiftUI
import SwiftData
import SwiftDataPreviewer

@main
struct PetApp: App {
    let container: ModelContainer
    let model: DataModel

    init() {
        container = ModelContainerFactory.create(
            Pet.self,
            TrainingSession.self
        )

        model = DataModel(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .modelContainer(container)
        }
    }
}
```

---

## 2) Preview setup (recommended pattern)

Create a single app-level preview config.

```swift
import SwiftData
import SwiftDataPreviewer

enum PetPreviewConfig: SwiftDataPreviewContextConfig {
    static let models: [any PersistentModel.Type] = [
        Pet.self,
        TrainingSession.self
    ]

    @MainActor
    static func seed(_ context: ModelContext) {
        context.insert(Pet.samplePets)
        context.insert(TrainingSession.sampleSessions)
    }
}
```

> Tip: You should only need **one** config per app.

---

## 3) Simple seeded previews (no extra dependencies)

Use `PreviewTrait.seeded(...)`:

```swift
import SwiftUI
import SwiftDataPreviewer

#Preview(traits: .seeded(PetPreviewConfig.self)) {
    PetRowView(pet: .samplePet)
}
```

If you prefer a global alias:

```swift
extension PreviewTrait {
    @MainActor
    static var devData: PreviewTrait {
        .seeded(PetPreviewConfig.self)
    }
}

#Preview(traits: .devData) {
    PetRowView(pet: .samplePet)
}
```

---

## 4) Previews with dependencies (unlimited)

Define a single `ViewModifier` that builds and injects anything you need:

```swift
import SwiftUI
import SwiftData

struct PreviewDependencies: ViewModifier {
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .environment(DataModel(context: context))
            .environment(SettingsStore())
            // Add as many as you want:
            // .environment(AnalyticsModel())
            // .preferredColorScheme(.dark)
    }
}
```

Then use `PreviewTrait.dev(...)`:

```swift
import SwiftUI
import SwiftDataPreviewer

#Preview(traits: .dev(PetPreviewConfig.self) { ctx in
    PreviewDependencies(context: ctx)
}) {
    PetRowView(pet: .samplePet)
}
```

Or with an alias:

```swift
extension PreviewTrait {
    @MainActor
    static var devData: PreviewTrait {
        .dev(PetPreviewConfig.self) { ctx in
            PreviewDependencies(context: ctx)
        }
    }
}
```

---

## 5) Seed helpers

The package includes convenience insert APIs:

```swift
@MainActor
static func seed(_ context: ModelContext) {
    context.insert(Pet.samplePets)
    context.insert(TrainingSession.sampleSessions)
}
```

You can also insert individual instances:

```swift
context.insert(Pet.samplePet)
```

---

## Testing

This package ships with XCTest coverage for:
- `ModelContainerFactory` success paths
- `ModelContext.insert(...)` helpers
- Preview trait constructors (`seeded` and `dev`)
- `DataPreviewer` creation and static context setup through a test config

To run tests in Xcode:
1. Select the `SwiftDataPreviewer` scheme.
2. Press **⌘U**.

**Note on 100% coverage:**  
If your implementation uses `fatalError(...)` for container creation failures, the failure branch is difficult to execute in unit tests without introducing a small test hook (e.g., an injectable error handler). If you want strict 100% line/branch coverage reports, consider adding a debug-only override point in `ModelContainerFactory` for tests. The included tests aim to cover all practical, non-crashing paths.

---

## Philosophy

This package intentionally avoids:
- `AnyView`-based type erasure
- “infinite environment injection” APIs
- heavy macro systems

Instead, it gives you:
- a small, stable core
- app-authored `ViewModifier` injection for unlimited flexibility
- minimal per-app setup

---

## Suggested file layout in your app

```
App/
  PetApp.swift

Models/
  Pet.swift
  TrainingSession.swift
  SampleData+Pet.swift

PreviewSupport/
  PetPreviewConfig.swift
  PreviewDependencies.swift (optional)
  PreviewTrait+DevData.swift
```

---

## Quick start checklist

For each new SwiftData app:

1. ✅ Add models
2. ✅ Create one preview config
3. ✅ (Optional) create one `PreviewDependencies` modifier
4. ✅ Add a `.devData` alias
5. ✅ Use `#Preview(traits: .devData)` everywhere

---

## License

MIT

