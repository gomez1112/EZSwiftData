//
//  ModelContext+Extension.swift
//  EZSwiftData
//
//  Created by Gerard Gomez on 12/6/25.
//


import SwiftData

public extension ModelContext {

    /// Inserts a sequence of models.
    @MainActor
    func insert<S: Sequence>(_ models: S) where S.Element: PersistentModel {
        for model in models {
            insert(model)
        }
    }

    /// Inserts a variadic list of models.
    @MainActor
    func insert<T: PersistentModel>(_ models: T...) {
        for model in models {
            insert(model)
        }
    }
}
