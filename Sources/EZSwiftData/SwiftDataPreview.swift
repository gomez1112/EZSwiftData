import SwiftData
import SwiftUI

/// A preview view that exposes its seeded `ModelContext` to the content builder.
///
/// Use this inside `#Preview` when the previewed view receives dependencies
/// through its initializer rather than through the environment.
@MainActor
public struct SwiftDataPreview<
    Config: SwiftDataPreviewContextConfig,
    Content: View
>: View {
    private let container: ModelContainer
    private let content: Content

    public init(
        _ config: Config.Type,
        @ViewBuilder content: (ModelContext) throws -> Content
    ) {
        do {
            let result = try Self.makeContent(
                config,
                content: content
            )
            container = result.0
            self.content = result.1
        } catch {
            fatalError("Failed to create SwiftData preview content: \(error)")
        }
    }

    public var body: some View {
        content
            .modelContainer(container)
    }

    static func makeContent(
        _ config: Config.Type,
        content: (ModelContext) throws -> Content
    ) throws -> (ModelContainer, Content) {
        let container = try ModelContainerFactory.create(
            for: config.models,
            isStoredInMemoryOnly: true
        )
        let context = container.mainContext
        try config.seed(context)
        try context.save()
        return (container, try content(context))
    }
}
