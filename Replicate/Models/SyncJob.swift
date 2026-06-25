import Foundation

struct SyncJob: Identifiable, Codable, Equatable {
    static let defaultRcloneTransferCount = 16
    static let minRcloneTransferCount = 1
    static let maxRcloneTransferCount = 64

    var id: UUID
    var name: String
    var isEnabled: Bool
    var deleteExtraneousFiles: Bool
    var watchEnabled: Bool
    var rcloneTransferCount: Int {
        didSet {
            rcloneTransferCount = Self.clampedRcloneTransferCount(rcloneTransferCount)
        }
    }
    var sourceBookmark: Data?
    var destinationBookmark: Data?
    var sourceDisplayPath: String
    var destinationDisplayPath: String
    var lastRunDate: Date?
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        name: String = "New Sync Job",
        isEnabled: Bool = true,
        deleteExtraneousFiles: Bool = false,
        watchEnabled: Bool = false,
        rcloneTransferCount: Int = Self.defaultRcloneTransferCount,
        sourceBookmark: Data? = nil,
        destinationBookmark: Data? = nil,
        sourceDisplayPath: String = "",
        destinationDisplayPath: String = "",
        lastRunDate: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.deleteExtraneousFiles = deleteExtraneousFiles
        self.watchEnabled = watchEnabled
        self.rcloneTransferCount = Self.clampedRcloneTransferCount(rcloneTransferCount)
        self.sourceBookmark = sourceBookmark
        self.destinationBookmark = destinationBookmark
        self.sourceDisplayPath = sourceDisplayPath
        self.destinationDisplayPath = destinationDisplayPath
        self.lastRunDate = lastRunDate
        self.lastErrorMessage = lastErrorMessage
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Job" : trimmed
    }

    var isConfigured: Bool {
        sourceBookmark != nil && destinationBookmark != nil
    }

    static func clampedRcloneTransferCount(_ value: Int) -> Int {
        min(max(value, minRcloneTransferCount), maxRcloneTransferCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case deleteExtraneousFiles
        case watchEnabled
        case rcloneTransferCount
        case sourceBookmark
        case destinationBookmark
        case sourceDisplayPath
        case destinationDisplayPath
        case lastRunDate
        case lastErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        deleteExtraneousFiles = try container.decode(Bool.self, forKey: .deleteExtraneousFiles)
        watchEnabled = try container.decode(Bool.self, forKey: .watchEnabled)
        rcloneTransferCount = Self.clampedRcloneTransferCount(
            try container.decodeIfPresent(Int.self, forKey: .rcloneTransferCount) ?? Self.defaultRcloneTransferCount
        )
        sourceBookmark = try container.decodeIfPresent(Data.self, forKey: .sourceBookmark)
        destinationBookmark = try container.decodeIfPresent(Data.self, forKey: .destinationBookmark)
        sourceDisplayPath = try container.decode(String.self, forKey: .sourceDisplayPath)
        destinationDisplayPath = try container.decode(String.self, forKey: .destinationDisplayPath)
        lastRunDate = try container.decodeIfPresent(Date.self, forKey: .lastRunDate)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(deleteExtraneousFiles, forKey: .deleteExtraneousFiles)
        try container.encode(watchEnabled, forKey: .watchEnabled)
        try container.encode(rcloneTransferCount, forKey: .rcloneTransferCount)
        try container.encodeIfPresent(sourceBookmark, forKey: .sourceBookmark)
        try container.encodeIfPresent(destinationBookmark, forKey: .destinationBookmark)
        try container.encode(sourceDisplayPath, forKey: .sourceDisplayPath)
        try container.encode(destinationDisplayPath, forKey: .destinationDisplayPath)
        try container.encodeIfPresent(lastRunDate, forKey: .lastRunDate)
        try container.encodeIfPresent(lastErrorMessage, forKey: .lastErrorMessage)
    }
}

struct ResolvedSyncJob {
    let job: SyncJob
    let sourceURL: URL
    let destinationURL: URL
    let scopedAccess: [SecurityScopedURLAccess]
}

enum SyncJobResolutionError: LocalizedError {
    case missingSource
    case missingDestination
    case staleBookmark(String)
    case unavailableFolder(String)

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Choose a source folder."
        case .missingDestination:
            return "Choose a destination folder."
        case .staleBookmark(let label):
            return "\(label) access is stale. Re-select the folder."
        case .unavailableFolder(let path):
            return "Folder is unavailable: \(path)"
        }
    }
}
