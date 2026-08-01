#if canImport(CloudKit) && canImport(SwiftData)
import SwiftData

/// Main-actor merge policy implemented by an application-specific SwiftData cache.
@MainActor
public protocol CloudKitSwiftDataMergeDelegate: AnyObject {
    /// Applies immutable remote snapshots and tombstones. The delegate decides whether tombstones delete local data.
    func apply(_ changes: [CloudKitRecordSnapshot], deletions: [CloudKitRecordDeletion], in context: ModelContext) throws
}

/// A main-actor adapter that never retains or transfers a `ModelContext` across actor boundaries.
@MainActor
public struct CloudKitSwiftDataBridge {
    private weak var delegate: (any CloudKitSwiftDataMergeDelegate)?
    public init(delegate: any CloudKitSwiftDataMergeDelegate) { self.delegate = delegate }
    public func merge(changes: [CloudKitRecordSnapshot], deletions: [CloudKitRecordDeletion], in context: ModelContext) throws {
        try delegate?.apply(changes, deletions: deletions, in: context)
    }
}
#endif
