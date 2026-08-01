import CloudKit
import EZSwiftData
import UIKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    @MainActor var router: CloudKitShareAcceptanceRouter?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        for metadata in connectionOptions.cloudKitShareMetadata { Task { @MainActor in await router?.handle(metadata) } }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await router?.handle(metadata) }
    }
}
