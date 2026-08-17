#if canImport(CloudKit)
  import CloudKit

  /// Accepts CloudKit invitations delivered during either cold or warm launch and resolves their collaboration zone.
  @MainActor
  public struct CloudKitShareAcceptanceRouter {
    public init() {}

    @discardableResult
    public func accept(
      _ metadata: CKShare.Metadata,
      containerIdentifier: String
    ) async throws -> CloudKitZoneIdentity {
      let container = CKContainer(identifier: containerIdentifier)
      _ = try await container.accept(metadata)
      return CloudKitZoneIdentity(metadata.share.recordID.zoneID)
    }
  }
#endif
