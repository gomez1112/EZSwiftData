#if canImport(CloudKit)
  @preconcurrency import CloudKit
  import Foundation

  /// Full-control mapping for models that need native fields, assets, references, or queries.
  public protocol CloudKitRecordRepresentable: CloudShareable {
    func makeCloudKitRecord(identifier: CKRecord.ID) throws -> CKRecord
    static func decodeCloudKitRecord(_ record: CKRecord) throws -> Self
  }

  /// The default payload mapper. Advanced models can bypass it by adopting
  /// `CloudKitRecordRepresentable`.
  public enum CloudRecordMapper {
    public static let payloadKey = "cloudPayload"
    public static let versionKey = "cloudModelVersion"

    public static func record<Model: CloudShareable>(
      for model: Model,
      identifier: CKRecord.ID
    ) throws -> CKRecord {
      if let custom = model as? any CloudKitRecordRepresentable {
        return try custom.makeCloudKitRecord(identifier: identifier)
      }
      let record = CKRecord(recordType: Model.cloudRecordType, recordID: identifier)
      do {
        record[payloadKey] = try JSONEncoder().encode(model) as CKRecordValue
        record[versionKey] = Model.cloudModelVersion as CKRecordValue
        return record
      } catch {
        throw CloudKitSharingError.modelEncodingFailed(String(describing: error))
      }
    }

    public static func model<Model: CloudShareable>(
      _ type: Model.Type = Model.self,
      from record: CKRecord
    ) throws -> Model {
      if let custom = Model.self as? any CloudKitRecordRepresentable.Type,
        let value = try custom.decodeCloudKitRecord(record) as? Model
      {
        return value
      }
      guard let payload = record[payloadKey] as? Data else {
        throw CloudKitSharingError.modelDecodingFailed("Missing \(payloadKey)")
      }
      do { return try JSONDecoder().decode(Model.self, from: payload) } catch {
        throw CloudKitSharingError.modelDecodingFailed(String(describing: error))
      }
    }
  }
#endif
