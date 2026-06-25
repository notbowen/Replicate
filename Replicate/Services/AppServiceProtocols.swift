import Foundation

@MainActor
protocol JobStoring {
    func load() -> [SyncJob]
    func save(_ jobs: [SyncJob])
}

@MainActor
protocol SyncJobResolving {
    func resolve(_ job: SyncJob) throws -> ResolvedSyncJob
}

@MainActor
protocol RcloneServicing {
    var isRunning: Bool { get }

    func preview(_ resolvedJob: ResolvedSyncJob) async throws -> [PendingItem]
    func sync(_ resolvedJob: ResolvedSyncJob) async throws -> SyncRunSummary
    func cancel()
}

@MainActor
protocol FswatchServicing {
    var activeJobIDs: Set<UUID> { get }
    var lastErrorMessage: String? { get }

    func configure(
        jobs: [ResolvedSyncJob],
        isPaused: Bool,
        onChange: @escaping @MainActor (UUID) -> Void
    )
    func stop(jobID: UUID)
    func stopAll()
    func executableStatusMessage() -> String?
}

struct BookmarkSyncJobResolver: SyncJobResolving {
    func resolve(_ job: SyncJob) throws -> ResolvedSyncJob {
        guard let sourceBookmark = job.sourceBookmark else {
            throw SyncJobResolutionError.missingSource
        }

        guard let destinationBookmark = job.destinationBookmark else {
            throw SyncJobResolutionError.missingDestination
        }

        let source = try BookmarkResolver.resolve(sourceBookmark, label: "Source").url
        let destination = try BookmarkResolver.resolve(destinationBookmark, label: "Destination").url
        return ResolvedSyncJob(
            job: job,
            sourceURL: source,
            destinationURL: destination,
            scopedAccess: [
                SecurityScopedURLAccess(url: source),
                SecurityScopedURLAccess(url: destination)
            ]
        )
    }
}
