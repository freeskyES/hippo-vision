import Foundation

// MARK: - Operation Asset Display Model

/// View 레이어 전용 OperationAsset 모델
public struct OperationAssetDisplayModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileName: String
    public let fileURL: URL
    public let createdAt: Date

    public init(id: String, fileName: String, createdAt: Date, fileURL: URL) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.fileURL = fileURL
    }
}

public extension OperationAssetDisplayModel {
    func toDomain() -> OperationAsset {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            print("Failed to read file data from \(fileURL): \(error)")
            fileData = Data()
        }

        return OperationAsset(
            id: id,
            fileData: fileData,
            originalFileName: fileName,
            createdAt: createdAt
        )
    }
}
