#if canImport(CloudKit) && canImport(SwiftUI) && !os(watchOS)
  import CloudKit
  import SwiftUI
  #if canImport(UIKit)
    import UIKit

    /// A SwiftUI wrapper around Apple's participant-management controller.
    public struct CloudKitSharingView: UIViewControllerRepresentable {
      public typealias UIViewControllerType = UICloudSharingController
      private let share: CKShare
      private let container: CKContainer
      private let preparationHandler: (@MainActor (Result<Void, any Error>) -> Void)?

      public init(
        share: CKShare,
        container: CKContainer,
        preparationHandler: (@MainActor (Result<Void, any Error>) -> Void)? = nil
      ) {
        self.share = share
        self.container = container
        self.preparationHandler = preparationHandler
      }

      public func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
      }

      public func updateUIViewController(_ controller: UICloudSharingController, context: Context) {
      }
      public func makeCoordinator() -> Coordinator {
        Coordinator(preparationHandler: preparationHandler)
      }

      @MainActor
      public final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let preparationHandler: (@MainActor (Result<Void, any Error>) -> Void)?
        init(preparationHandler: (@MainActor (Result<Void, any Error>) -> Void)?) {
          self.preparationHandler = preparationHandler
        }
        public func itemTitle(for controller: UICloudSharingController) -> String? { nil }
        public func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
          preparationHandler?(.success(()))
        }
        public func cloudSharingController(
          _ controller: UICloudSharingController,
          failedToSaveShareWithError error: any Error
        ) { preparationHandler?(.failure(error)) }
        public func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {}
      }
    }
  #endif
#endif
