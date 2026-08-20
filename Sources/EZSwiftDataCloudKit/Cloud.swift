#if canImport(CloudKit)
  @preconcurrency import CloudKit
  import Foundation

  public struct CloudConfiguration: Hashable, Sendable {
    public var containerIdentifier: String
    public init(containerIdentifier: String) { self.containerIdentifier = containerIdentifier }
  }

  public enum CloudAccountStatus: Hashable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
  }

  /// The package's progressive-disclosure entry point.
  public actor Cloud {
    /// Uses the default CloudKit container declared by the consuming app's entitlements.
    ///
    /// This mirrors SwiftData's default-container behavior. Create a ``Cloud`` with an
    /// explicit ``CloudConfiguration`` only when selecting a non-default container.
    public static let `default` = Cloud(configuration: .init(containerIdentifier: ""))

    public let configuration: CloudConfiguration
    private let container: CKContainer

    public init(configuration: CloudConfiguration) {
      self.configuration = configuration
      container =
        configuration.containerIdentifier.isEmpty
        ? .default()
        : CKContainer(identifier: configuration.containerIdentifier)
    }

    public var accountStatus: CloudAccountStatus {
      get async {
        do {
          return switch try await container.accountStatus() {
          case .available: .available
          case .noAccount: .noAccount
          case .restricted: .restricted
          case .temporarilyUnavailable: .temporarilyUnavailable
          case .couldNotDetermine: .couldNotDetermine
          @unknown default: .couldNotDetermine
          }
        } catch { return .couldNotDetermine }
      }
    }

    public func share<Model: CloudShareable>(
      _ model: Model,
      options: CloudShareOptions = .init()
    ) async throws -> CloudShare<Model> {
      let database = container.privateCloudDatabase
      let zone = try await database.save(CKRecordZone(zoneName: UUID().uuidString))
      let identifier = CKRecord.ID(recordName: String(describing: model.id), zoneID: zone.zoneID)
      let root = try CloudRecordMapper.record(for: model, identifier: identifier)
      let share = CKShare(rootRecord: root)
      if let title = options.title { share[CKShare.SystemFieldKey.title] = title as CKRecordValue }
      share.publicPermission =
        switch options.access {
        case .private: .none
        case .publicReadOnly: .readOnly
        case .publicReadWrite: .readWrite
        }
      let results = try await database.modifyRecords(saving: [root, share], deleting: [])
      guard let saved = results.saveResults[share.recordID],
        let savedShare = try saved.get() as? CKShare
      else { throw CloudKitSharingError.shareWasNotSaved }
      return CloudShare(
        model: model, share: savedShare, containerIdentifier: configuration.containerIdentifier)
    }

    public func invitation(from shareURL: CloudShareURL) async throws -> CloudShareInvitation {
      let metadata = try await container.shareMetadata(for: shareURL.url)
      return CloudShareInvitation(metadata: metadata, container: container)
    }

    /// Accepts several invitations while retaining every per-item result.
    public func accept(_ invitations: [CloudShareInvitation]) async -> [Result<
      CloudShareAcceptance, Error
    >] {
      var results: [Result<CloudShareAcceptance, Error>] = []
      for invitation in invitations {
        do { results.append(.success(try await invitation.accept())) } catch {
          results.append(.failure(error))
        }
      }
      return results
    }
  }

  public struct CloudShare<Model: CloudShareable> {
    public let model: Model
    public let cloudKitShare: CKShare
    public let containerIdentifier: String
    public var url: URL? { cloudKitShare.url }
    public var participants: [CKShare.Participant] { cloudKitShare.participants }
  }

  public struct CloudShareAcceptance: Sendable {
    public let zone: CloudKitZoneIdentity
    public init(zone: CloudKitZoneIdentity) { self.zone = zone }
  }

  public struct CloudShareInvitation {
    public let metadata: CKShare.Metadata
    private let container: CKContainer
    init(metadata: CKShare.Metadata, container: CKContainer) {
      self.metadata = metadata
      self.container = container
    }
    public func accept() async throws -> CloudShareAcceptance {
      _ = try await container.accept(metadata)
      return .init(zone: .init(metadata.share.recordID.zoneID))
    }
    public func accept<Model: CloudShareable>(as type: Model.Type) async throws -> Model {
      _ = try await accept()
      let record = try await container.sharedCloudDatabase.record(for: metadata.rootRecordID)
      return try CloudRecordMapper.model(type, from: record)
    }
  }
#endif
