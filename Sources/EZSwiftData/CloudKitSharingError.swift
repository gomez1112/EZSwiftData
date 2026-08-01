#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation

/// A contextual CloudKit sharing failure with presentation-ready diagnostics.
public struct CloudKitSharingFailure: LocalizedError, @unchecked Sendable {
    /// The operation that failed.
    public let operation: String
    /// The underlying error retained for diagnostics. `CKError` is immutable after creation.
    public let underlyingError: Error
    /// CloudKit's requested delay, when supplied.
    public let retryAfter: Duration?

    public init(operation: String, underlyingError: Error) {
        self.operation = operation; self.underlyingError = underlyingError
        if let seconds = (underlyingError as? CKError)?.userInfo[CKErrorRetryAfterKey] as? Double {
            retryAfter = .seconds(seconds)
        } else { retryAfter = nil }
    }

    public var errorDescription: String? {
        if let error = underlyingError as? CKError {
            switch error.code {
            case .notAuthenticated: return "Sign in to iCloud and enable iCloud Drive before \(operation)."
            case .permissionFailure: return "You do not have permission to \(operation). The owner may need to change your access."
            case .quotaExceeded: return "The iCloud storage quota was exceeded while attempting to \(operation)."
            case .networkUnavailable, .networkFailure: return "The network is unavailable. Connect to the internet and try to \(operation) again."
            case .serviceUnavailable: return "CloudKit is temporarily unavailable. Try again later."
            case .requestRateLimited: return "CloudKit is receiving too many requests. Try again after the requested delay."
            case .partialFailure: return "CloudKit completed only part of the request to \(operation). Inspect the partial errors for affected items."
            default:
                if error.localizedDescription.localizedStandardContains("recordName") && error.localizedDescription.localizedStandardContains("queryable") {
                    return "The CloudKit schema does not mark recordName QUERYABLE for this record type. In CloudKit Console, select this container and the same Development or Production environment as the build, then add a QUERYABLE recordName index."
                }
                return "CloudKit could not \(operation): \(error.localizedDescription)"
            }
        }
        return "Could not \(operation): \(underlyingError.localizedDescription)"
    }
}

/// Recoverable configuration and lifecycle errors.
public enum CloudKitSharingError: LocalizedError, Equatable, Sendable {
    case emptyContainerIdentifier, emptyZoneName, emptyRecordType
    case operationRequiresPrivateDatabase, shareWasNotSaved, shareURLUnavailable
    case containerMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .emptyContainerIdentifier: "A nonempty CloudKit container identifier is required."
        case .emptyZoneName: "A nonempty CloudKit record-zone name is required."
        case .emptyRecordType: "A nonempty CloudKit record type is required."
        case .operationRequiresPrivateDatabase: "This operation manages ownership or sharing and therefore requires the private database."
        case .shareWasNotSaved: "CloudKit did not return a saved CKShare."
        case .shareURLUnavailable: "CloudKit saved the share without a URL. Save the share on the server before presenting participant management."
        case let .containerMismatch(expected, actual): "The invitation belongs to \(actual), but this coordinator uses \(expected)."
        }
    }
}

/// Bounded retry behavior for transient CloudKit failures.
public struct CloudKitRetryPolicy: Sendable {
    public var maximumAttempts: Int
    public var initialDelay: Duration
    public var maximumDelay: Duration
    public var jitter: Double
    public init(maximumAttempts: Int = 4, initialDelay: Duration = .seconds(1), maximumDelay: Duration = .seconds(30), jitter: Double = 0.2) {
        self.maximumAttempts = max(1, maximumAttempts); self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay; self.jitter = min(max(jitter, 0), 1)
    }
    public static let `default` = CloudKitRetryPolicy()
    public func isRetryable(_ error: Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return [.networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy].contains(code)
    }
}
#endif
