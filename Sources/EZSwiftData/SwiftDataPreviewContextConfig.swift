//
//  SwiftDataPreviewContextConfig.swift
//  EZSwiftData
//
//  Created by Gerard Gomez on 12/6/25.
//


import SwiftData

/// Minimal per-app preview configuration.
/// Your app owns:
/// - the model list
/// - the sample data insertion logic
public protocol SwiftDataPreviewContextConfig {
    static var models: [any PersistentModel.Type] { get }
    @MainActor static func seed(_ context: ModelContext)
}

public extension SwiftDataPreviewContextConfig {
    @MainActor static func seed(_ context: ModelContext) { }
}
