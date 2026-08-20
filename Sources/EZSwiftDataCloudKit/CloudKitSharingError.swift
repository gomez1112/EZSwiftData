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
  case invalidShareURL
  case modelEncodingFailed(String)
  case modelDecodingFailed(String)
  case invitationUnavailable
  case unsupportedOperation(String)
  case unsupportedRecordType(String)
  case recordConversionFailed(String)
}
