//
//  DataPreviewer.swift
//  EZSwiftData
//
//  Created by Gerard Gomez on 12/6/25.
//


import SwiftUI
import SwiftData

// MARK: - Preview Helper (Generic ViewModifier)

/// A PreviewModifier that:
/// 1) Builds an in-memory SwiftData container from `Config.models`
/// 2) Seeds it using `Config.seed`
/// 3) Applies a caller-provided `ViewModifier` built from the `ModelContext`
///
/// This design lets you inject unlimited preview-only dependencies
/// without `AnyView` and without arity-limited APIs.
public struct DataPreviewer<
    Config: SwiftDataPreviewContextConfig,
    VM: ViewModifier
>: PreviewModifier {

    public typealias Context = ModelContainer

    private let modifierBuilder: @MainActor (ModelContext) -> VM

    /// Initializes the preview helper.
    ///
    /// - Parameter modifier: A closure that creates a concrete `ViewModifier`
    ///   containing your environments and any other preview-only tweaks.
    public init(
        modifier: @escaping @MainActor (ModelContext) -> VM
    ) {
        self.modifierBuilder = modifier
    }

    // PreviewModifier requires a *static* shared-context factory.
    public static func makeSharedContext() async throws -> ModelContainer {
        let container = ModelContainerFactory.create(
            for: Config.models,
            isStoredInMemoryOnly: true
        )

        await MainActor.run {
            Config.seed(container.mainContext)
        }

        return container
    }

    @MainActor
    public func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(modifierBuilder(context.mainContext))
            .modelContainer(context)
    }
}
