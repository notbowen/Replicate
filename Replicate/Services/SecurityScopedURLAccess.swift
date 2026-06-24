import Foundation

final class SecurityScopedURLAccess {
    let url: URL
    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum BookmarkResolver {
    static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ bookmarkData: Data, label: String) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard !isStale else {
            throw SyncJobResolutionError.staleBookmark(label)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncJobResolutionError.unavailableFolder(url.path)
        }

        return (url, isStale)
    }
}
