#if canImport(CloudKit)
@preconcurrency import CloudKit
import Observation

/// Main-actor forwarding endpoint for cold- and warm-launch CloudKit invitation callbacks.
@MainActor @Observable
public final class CloudKitShareAcceptanceRouter {
    public private(set) var isAccepting = false
    public private(set) var lastAcceptedShare: AcceptedCloudKitShare?
    public private(set) var lastErrorDescription: String?
    public let acceptedShares: AsyncStream<AcceptedCloudKitShare>
    private let continuation: AsyncStream<AcceptedCloudKitShare>.Continuation
    private let coordinator: CloudKitSharingCoordinator

    public init(coordinator: CloudKitSharingCoordinator) {
        self.coordinator = coordinator
        let pair = AsyncStream<AcceptedCloudKitShare>.makeStream(bufferingPolicy: .bufferingNewest(16))
        acceptedShares = pair.stream; continuation = pair.continuation
    }
    public func handle(_ metadata: CKShare.Metadata) async {
        guard !isAccepting else { return }; isAccepting = true; defer { isAccepting = false }
        do { let result = try await coordinator.accept(metadata); lastAcceptedShare = result; lastErrorDescription = nil; continuation.yield(result) }
        catch { lastErrorDescription = error.localizedDescription }
    }
    deinit { continuation.finish() }
}
#endif
