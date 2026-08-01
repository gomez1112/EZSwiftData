import CloudKit
import EZSwiftData
import SwiftData
import SwiftUI

@main
struct EZCloudSharingSampleApp: App {
    @UIApplicationDelegateAdaptor(SampleAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SampleApplicationModel?
    private let container: ModelContainer?

    init() {
        let schema = Schema([SharedNote.self])
        // Never let SwiftData automatic CloudKit sync manage the records managed
        // by EZSwiftData's explicit CKShare layer. SwiftData is a local cache.
        let configuration = ModelConfiguration("LocalCache", schema: schema, cloudKitDatabase: .none)
        container = try? ModelContainer(for: schema, configurations: configuration)
        _model = State(initialValue: try? SampleApplicationModel())
    }
    var body: some Scene {
        WindowGroup { SampleRootView(model: model, container: container, appDelegate: appDelegate) }
            .onChange(of: scenePhase) { _, phase in if phase == .active, let model { Task { await model.becameActive() } } }
    }
}

struct SampleRootView: View {
    let model: SampleApplicationModel?
    let container: ModelContainer?
    let appDelegate: SampleAppDelegate
    var body: some View {
        if let model, let container {
            SampleContentView(model: model).modelContainer(container).task { appDelegate.model = model; await model.start() }
        } else {
            ContentUnavailableView("Configuration Failed", systemImage: "exclamationmark.icloud", description: Text("Verify the CloudKit entitlement and local SwiftData schema."))
        }
    }
}

struct SampleContentView: View {
    @Bindable var model: SampleApplicationModel
    @Query private var notes: [SharedNote]
    @Environment(\.modelContext) private var context
    @State private var presentsSharing = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { note in
                    VStack(alignment: .leading) { Text(note.title).bold(); Text(note.bodyText) }
                        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(note) }; Button("Share", systemImage: "person.badge.plus") { Task { await model.prepareShare(for: note); presentsSharing = model.share != nil } } }
                }
            }
            .navigationTitle("Shared Notes")
            .toolbar { Button("Add Note", systemImage: "plus") { context.insert(SharedNote(title: "New note", bodyText: "Collaborate here")) } }
            .refreshable { await model.manualRefresh() }
            .sheet(isPresented: $presentsSharing) { if let share = model.share { NavigationStack { EZCloudSharingView(share: share, containerIdentifier: model.containerIdentifier, title: "Shared Note") } } }
        }
    }
}

final class SampleAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor weak var model: SampleApplicationModel?
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let model else { return .noData }
        do { try await model.processRemoteNotification(userInfo); return .newData } catch { return .failed }
    }
}
