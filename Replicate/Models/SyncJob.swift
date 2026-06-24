import Foundation

struct SyncJob: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var deleteExtraneousFiles: Bool
    var watchEnabled: Bool
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
