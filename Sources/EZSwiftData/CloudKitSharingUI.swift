#if canImport(CloudKit) && canImport(SwiftUI) && !os(watchOS)
@preconcurrency import CloudKit
import Observation
import SwiftUI

/// Presentation-safe collaboration information used by ``CloudKitSharingViewModel``.
public struct CloudKitCollaborationPresentation: Identifiable, Sendable {
    public let summary: CloudKitCollaborationSummary
    public let participants: [CloudKitParticipantInfo]
    public var id: String { summary.id }
    public init(summary: CloudKitCollaborationSummary, participants: [CloudKitParticipantInfo]) { self.summary = summary; self.participants = participants }
}

/// An alert-ready sharing error.
public struct CloudKitSharingPresentationError: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public init(title: String = "CloudKit Sharing", message: String) { id = UUID(); self.title = title; self.message = message }
}

/// Observable state for account checks, invitation acceptance, sharing, and synchronization UI.
@MainActor @Observable
public final class CloudKitSharingViewModel {
    public enum State: Equatable, Sendable { case idle, checkingAccount, preparingShare, presentingShare, acceptingInvitation, synchronizing, ready, failed }
    public private(set) var state: State = .idle
    public private(set) var currentCollaboration: CloudKitCollaborationPresentation?
    public var presentedError: CloudKitSharingPresentationError?
    public init() {}
    public func transition(to state: State) { self.state = state }
    public func present(_ collaboration: CloudKitCollaborationPresentation) { currentCollaboration = collaboration; state = .presentingShare }
    public func fail(with error: Error) { presentedError = .init(message: error.localizedDescription); state = .failed }
    public func clearError() { presentedError = nil; if state == .failed { state = .idle } }
}

/// Apple-native participant management and sharing UI for a server-saved `CKShare`.
///
/// The system view supplies Messages, Mail, permission changes, participant removal,
/// and stop-sharing actions according to device capabilities and the current user's role.
@available(iOS 16.0, macOS 13.0, *)
public struct EZCloudSharingView: View {
    private let share: CKShare
    private let container: CKContainer
    private let title: String?
    private let availablePermissions: CKSharingParticipantAccessOption
    private let onSave: @MainActor () -> Void
    private let onStopSharing: @MainActor () -> Void
    private let onFailure: @MainActor (Error) -> Void

    public init(share: CKShare, containerIdentifier: String, title: String? = nil, availablePermissions: CKSharingParticipantAccessOption = [.allowPrivate, .allowReadOnly, .allowReadWrite], onSave: @escaping @MainActor () -> Void = {}, onStopSharing: @escaping @MainActor () -> Void = {}, onFailure: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.share = share; container = CKContainer(identifier: containerIdentifier); self.title = title
        self.availablePermissions = availablePermissions; self.onSave = onSave
        self.onStopSharing = onStopSharing; self.onFailure = onFailure
    }
    public var body: some View {
        CloudSharingView(share: share, container: container)
            .availableSharingPermissions(availablePermissions)
            .navigationTitle(title ?? "Manage Sharing")
    }
}
#endif
