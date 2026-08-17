#if canImport(CloudKit)
  import CloudKit
  import SwiftData

  /// A SwiftData model type that knows how to merge its CloudKit representation.
  /// Implementations execute on the model context's main actor and never receive a `CKRecord` across an actor boundary.
  @MainActor
  public protocol CloudKitRecordConvertible: PersistentModel {
    static var cloudKitRecordType: String { get }
    static func merge(_ record: CKRecord, into context: ModelContext) throws
    static func delete(_ recordID: CKRecord.ID, from context: ModelContext) throws
  }

  /// Applies sendable synchronization snapshots to registered SwiftData model adapters.
  @MainActor
  public struct CloudKitSwiftDataBridge {
    private let modelTypes: [any CloudKitRecordConvertible.Type]

    public init(modelTypes: [any CloudKitRecordConvertible.Type]) {
      self.modelTypes = modelTypes
    }

    public func apply(
      changed snapshots: [CloudKitRecordSnapshot],
      deleted deletions: [CloudKitRecordDeletion],
      to context: ModelContext
    ) throws {
      let models = Dictionary(uniqueKeysWithValues: modelTypes.map { ($0.cloudKitRecordType, $0) })
      for snapshot in snapshots {
        guard let model = models[snapshot.recordType] else {
          throw CloudKitSharingError.unsupportedRecordType(snapshot.recordType)
        }
        try model.merge(try snapshot.record(), into: context)
      }
      for deletion in deletions {
        guard let model = models[deletion.recordType] else {
          throw CloudKitSharingError.unsupportedRecordType(deletion.recordType)
        }
        try model.delete(deletion.identity.ckID, from: context)
      }
      if context.hasChanges { try context.save() }
    }
  }
#endif
