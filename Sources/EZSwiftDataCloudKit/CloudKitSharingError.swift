#if canImport(CloudKit)
  import Foundation

  /// Errors produced by the explicit CloudKit sharing APIs.
  public enum CloudKitSharingError: Swift.Error, Equatable, Sendable {
    case emptyContainerIdentifier
    case emptyZoneName
    case emptyRecordType
    case operationRequiresPrivateDatabase
    case shareWasNotSaved
    case subscriptionWasNotSaved
    case invalidShareMetadata
    case unsupportedRecordType(String)
    case recordConversionFailed(String)
  }
#endif
