//
//  PreviewTrait+Extension.swift
//  EZSwiftData
//
//  Created by Gerard Gomez on 12/6/25.
//


import SwiftUI
import SwiftData

public extension PreviewTrait where T == Preview.ViewTraits {

    /// A seeded SwiftData preview with no extra environment injection.
    static func seeded<Config: SwiftDataPreviewContextConfig>(
        _ config: Config.Type
    ) -> PreviewTrait {
        .modifier(DataPreviewer<Config, EmptyModifier> { _ in EmptyModifier() })
    }

    /// A seeded SwiftData preview that applies a custom ViewModifier
    /// built from the preview `ModelContext`.
    ///
    /// This is your “infinite dependencies” path without `AnyView`.
    static func dev<
        Config: SwiftDataPreviewContextConfig,
        VM: ViewModifier
    >(
        _ config: Config.Type,
        _ modifier: @escaping @MainActor (ModelContext) -> VM
    ) -> PreviewTrait {
        .modifier(DataPreviewer<Config, VM>(modifier: modifier))
    }

    /// A seeded SwiftData preview with no extra environment injection.
    ///
    /// Use this when you want the `.dev(...)` semantics but do not need
    /// additional preview dependencies yet.
    static func dev<Config: SwiftDataPreviewContextConfig>(
        _ config: Config.Type
    ) -> PreviewTrait {
        .modifier(DataPreviewer<Config, EmptyModifier> { _ in EmptyModifier() })
    }

    /// Backwards-compatible overload using the old labeled closure.
    @available(*, deprecated, renamed: "dev(_:_:)")
    static func dev<
        Config: SwiftDataPreviewContextConfig,
        VM: ViewModifier
    >(
        _ config: Config.Type,
        modifier: @escaping @MainActor (ModelContext) -> VM
    ) -> PreviewTrait {
        dev(config, modifier)
    }
}
