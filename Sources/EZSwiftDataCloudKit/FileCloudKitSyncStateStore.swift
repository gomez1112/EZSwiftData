#if canImport(CloudKit)
  import Foundation

  /// A durable JSON sync-state store. Corrupt state is removed so synchronization can recover with a full fetch.
  public actor FileCloudKitSyncStateStore: CloudKitSyncStateStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
      directory: URL = .applicationSupportDirectory.appending(
        path: "EZSwiftDataCloudKit", directoryHint: .isDirectory)
    ) {
      self.directory = directory
    }

    public func load(containerIdentifier: String) throws -> CloudKitSyncState {
      let url = fileURL(containerIdentifier: containerIdentifier)
      guard FileManager.default.fileExists(atPath: url.path()) else { return .init() }
      do {
        return try decoder.decode(CloudKitSyncState.self, from: Data(contentsOf: url))
      } catch {
        try? FileManager.default.removeItem(at: url)
        return .init()
      }
    }

    public func save(_ state: CloudKitSyncState, containerIdentifier: String) throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try encoder.encode(state).write(
        to: fileURL(containerIdentifier: containerIdentifier), options: .atomic)
    }

    public func remove(containerIdentifier: String) throws {
      let url = fileURL(containerIdentifier: containerIdentifier)
      if FileManager.default.fileExists(atPath: url.path()) {
        try FileManager.default.removeItem(at: url)
      }
    }

    /// Exposed to make corrupt-file recovery deterministic to test without duplicating filename rules.
    public func stateFileURL(containerIdentifier: String) -> URL {
      fileURL(containerIdentifier: containerIdentifier)
    }

    private func fileURL(containerIdentifier: String) -> URL {
      let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
      let sanitized = containerIdentifier.unicodeScalars.map {
        allowed.contains($0) ? Character(String($0)) : "_"
      }
      return directory.appending(path: "\(String(sanitized)).json")
    }
  }
#endif
