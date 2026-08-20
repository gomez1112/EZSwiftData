import Foundation

/// A normal Swift value that can be stored in, synchronized through, and shared with CloudKit.
///
/// `Codable` is the intentionally small beginner representation. Adopt
/// `CloudKitRecordRepresentable` when individual fields must be queryable.
public protocol CloudShareable: Codable, Identifiable, Sendable where ID: Codable & Sendable {
  static var cloudRecordType: String { get }
  static var cloudModelVersion: Int { get }
}

extension CloudShareable {
  public static var cloudRecordType: String { String(describing: Self.self) }
  public static var cloudModelVersion: Int { 1 }
}

/// Keeps an application's `Model.ID` separate from CloudKit's record identity.
public struct CloudRecordIdentifier<Model: CloudShareable>: Hashable, Codable, Sendable {
  public let recordName: String
  public let zoneName: String
  public let ownerName: String

  public init(recordName: String, zoneName: String, ownerName: String = "__defaultOwner__") {
    self.recordName = recordName
    self.zoneName = zoneName
    self.ownerName = ownerName
  }
}

/// Marks a value intended for a native, queryable CloudKit field in custom mappings.
@propertyWrapper public struct CloudField<Value: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: Value
  public let name: String?
  public init(wrappedValue: Value, _ name: String? = nil) {
    self.wrappedValue = wrappedValue
    self.name = name
  }
}

/// Marks a file URL that should be mapped to `CKAsset`, without loading the file into memory.
@propertyWrapper public struct CloudAsset<Value: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: Value
  public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

/// Marks application identity that should become a CloudKit record reference in custom mappings.
@propertyWrapper public struct CloudRelationship<Value: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: Value
  public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

/// Marks the parent in a CloudKit record hierarchy.
@propertyWrapper public struct CloudParent<Value: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: Value
  public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

/// Marks a value for CloudKit's encrypted-values dictionary in a custom mapping.
/// Encrypted values are not queryable or sortable in CloudKit.
@propertyWrapper public struct CloudEncrypted<Value: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: Value
  public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

public enum CloudShareAccess: Hashable, Codable, Sendable {
  case `private`
  case publicReadOnly
  case publicReadWrite
}

public enum CloudSharePermission: String, Codable, Sendable {
  case readOnly
  case readWrite
}

public struct CloudShareOptions: Hashable, Codable, Sendable {
  public var title: String?
  public var access: CloudShareAccess
  public var defaultPermission: CloudSharePermission

  public init(
    title: String? = nil,
    access: CloudShareAccess = .private,
    defaultPermission: CloudSharePermission = .readOnly
  ) {
    self.title = title
    self.access = access
    self.defaultPermission = defaultPermission
  }
}

/// A validated CloudKit share URL. Validation deliberately avoids retaining or logging its contents.
public struct CloudShareURL: Hashable, Codable, Sendable {
  public let url: URL

  public init(_ url: URL) throws {
    let host = url.host?.lowercased()
    guard url.scheme?.lowercased() == "https",
      host == "icloud.com" || host?.hasSuffix(".icloud.com") == true
    else { throw CloudKitSharingError.invalidShareURL }
    self.url = url
  }
}
