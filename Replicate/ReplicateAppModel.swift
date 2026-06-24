import AppKit
import Combine
import Foundation

@MainActor
final class ReplicateAppModel: ObservableObject {
    @Published var jobs: [SyncJob] {
        didSet {
            store.save(jobs)
            if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
                self.selectedJobID = jobs.first?.id
            }
        }
    }

    @Published var selectedJobID: UUID?
    @Published var pendingItems: [PendingItem] = []
    @Published var isRefreshingPendingItems = false
    @Published var isSyncing = false
    @Published var isWatchPaused = false
    @Published var statusMessage = "Ready"
    @Published var watchStatusMessage: String?
    @Published var lastSyncOutput = ""

    private let store: JobStore
    private let rsyncService: RsyncService
    private let fswatchService: FswatchService
    private var queuedSyncJobIDs: Set<UUID> = []
    private var watchDebounceTasks: [UUID: Task<Void, Never>] = [:]

    convenience init() {
        self.init(
            store: JobStore(),
            rsyncService: RsyncService(),
            fswatchService: FswatchService()
        )
    }

    init(
        store: JobStore,
        rsyncService: RsyncService,
        fswatchService: FswatchService
    ) {
        self.store = store
        self.rsyncService = rsyncService
        self.fswatchService = fswatchService
        self.jobs = Self.clearingCancellationErrors(from: store.load())
        self.selectedJobID = jobs.first?.id
        self.watchStatusMessage = fswatchService.executableStatusMessage()
        store.save(jobs)
    }

    var pendingCountText: String {
        switch pendingItems.count {
        case 0: "No pending items"
        case 1: "1 pending item"
        default: "\(pendingItems.count) pending items"
        }
    }

    var activeWatchCount: Int {
        fswatchService.activeJobIDs.count
    }

    var menuBarSystemImage: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath.circle.fill"
        }

        if jobs.contains(where: { $0.lastErrorMessage != nil }) {
            return "exclamationmark.triangle.fill"
        }

        if !pendingItems.isEmpty {
            return "tray.and.arrow.up.fill"
        }

        if activeWatchCount > 0 {
            return "eye.fill"
        }

        return "checkmark.circle"
    }

    func addJob() {
        let job = SyncJob(name: "Sync Job \(jobs.count + 1)")
        jobs.append(job)
        selectedJobID = job.id
        refreshWatchers()
    }

    func deleteSelectedJob() {
        guard let selectedJobID else { return }
        fswatchService.stop(jobID: selectedJobID)
        jobs.removeAll { $0.id == selectedJobID }
        pendingItems.removeAll { $0.jobID == selectedJobID }
        self.selectedJobID = jobs.first?.id
        refreshWatchers()
    }

    func jobsDidChange() {
        refreshWatchers()
    }

    func chooseSourceFolder(for jobID: UUID) {
        chooseFolder(title: "Choose Source Folder") { [weak self] url in
            self?.setFolder(url, for: jobID, isSource: true)
        }
    }

    func chooseDestinationFolder(for jobID: UUID) {
        chooseFolder(title: "Choose Destination Folder") { [weak self] url in
            self?.setFolder(url, for: jobID, isSource: false)
        }
    }

    func refreshPendingItems() {
        Task {
            await refreshPendingItems(matching: nil)
        }
    }

    func syncAll() {
        let jobIDs = Set(jobs.filter(\.isEnabled).map(\.id))
        Task {
            await sync(jobIDs: jobIDs)
        }
    }

    func sync(jobID: UUID) {
        Task {
            await sync(jobIDs: [jobID])
        }
    }

    func stopSync() {
        rsyncService.cancel()
        statusMessage = "Stopping sync..."
    }

    func toggleWatchPaused() {
        isWatchPaused.toggle()
        refreshWatchers()
    }

    func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func chooseFolder(title: String, completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        completion(url)
    }

    private func setFolder(_ url: URL, for jobID: UUID, isSource: Bool) {
        do {
            let bookmark = try BookmarkResolver.bookmarkData(for: url)
            updateJob(jobID) { job in
                if isSource {
                    job.sourceBookmark = bookmark
                    job.sourceDisplayPath = url.path
                } else {
                    job.destinationBookmark = bookmark
                    job.destinationDisplayPath = url.path
                }
                job.lastErrorMessage = nil
            }
            refreshWatchers()
            refreshPendingItems()
        } catch {
            setError(error.localizedDescription, for: jobID)
        }
    }

    private func refreshPendingItems(matching jobIDs: Set<UUID>?) async {
        isRefreshingPendingItems = true
        defer { isRefreshingPendingItems = false }

        var refreshedItems: [PendingItem] = []
        let jobsToRefresh = jobs.filter { job in
            job.isEnabled && job.isConfigured && (jobIDs == nil || jobIDs?.contains(job.id) == true)
        }

        for job in jobsToRefresh {
            do {
                let resolvedJob = try resolve(job)
                let items = try await rsyncService.preview(resolvedJob)
                refreshedItems.append(contentsOf: items)
                clearError(for: job.id)
            } catch ProcessRunnerError.cancelled {
                statusMessage = "Refresh stopped."
                return
            } catch is CancellationError {
                statusMessage = "Refresh stopped."
                return
            } catch {
                setError(error.localizedDescription, for: job.id)
            }
        }

        if let jobIDs {
            pendingItems.removeAll { jobIDs.contains($0.jobID) }
            pendingItems.append(contentsOf: refreshedItems)
            pendingItems.sort { $0.jobName.localizedStandardCompare($1.jobName) == .orderedAscending }
        } else {
            pendingItems = refreshedItems
        }

        statusMessage = pendingItems.isEmpty ? "Ready" : pendingCountText
    }

    private func sync(jobIDs: Set<UUID>) async {
        guard !jobIDs.isEmpty else { return }

        if isSyncing {
            queuedSyncJobIDs.formUnion(jobIDs)
            return
        }

        isSyncing = true
        statusMessage = "Syncing..."

        let jobsToSync = jobs.filter { job in
            job.isEnabled && job.isConfigured && jobIDs.contains(job.id)
        }

        for job in jobsToSync {
            do {
                let resolvedJob = try resolve(job)
                let summary = try await rsyncService.sync(resolvedJob)
                lastSyncOutput = summary.output
                markRunCompleted(for: job.id, at: summary.completedAt)
                clearError(for: job.id)
            } catch ProcessRunnerError.cancelled {
                statusMessage = "Sync stopped."
                break
            } catch is CancellationError {
                statusMessage = "Sync stopped."
                break
            } catch {
                setError(error.localizedDescription, for: job.id)
            }
        }

        isSyncing = false
        await refreshPendingItems(matching: jobIDs)

        let queued = queuedSyncJobIDs
        queuedSyncJobIDs.removeAll()
        if !queued.isEmpty {
            await sync(jobIDs: queued)
        }
    }

    private func refreshWatchers() {
        watchStatusMessage = fswatchService.executableStatusMessage()
        guard watchStatusMessage == nil else {
            fswatchService.stopAll()
            return
        }

        let watchJobs = jobs.compactMap { job -> ResolvedSyncJob? in
            guard job.isEnabled, job.watchEnabled, job.isConfigured else { return nil }
            do {
                return try resolve(job)
            } catch {
                setError(error.localizedDescription, for: job.id)
                return nil
            }
        }

        fswatchService.configure(jobs: watchJobs, isPaused: isWatchPaused) { [weak self] jobID in
            self?.handleWatchEvent(jobID: jobID)
        }

        watchStatusMessage = activeWatchCount > 0 ? "Watching \(activeWatchCount) job(s)" : fswatchService.lastErrorMessage
    }

    private func handleWatchEvent(jobID: UUID) {
        guard !isWatchPaused else { return }

        watchDebounceTasks[jobID]?.cancel()
        watchDebounceTasks[jobID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            await self?.autoSyncAfterWatchEvent(jobID: jobID)
        }
    }

    private func autoSyncAfterWatchEvent(jobID: UUID) async {
        await refreshPendingItems(matching: [jobID])
        guard pendingItems.contains(where: { $0.jobID == jobID }) else { return }
        await sync(jobIDs: [jobID])
    }

    private func resolve(_ job: SyncJob) throws -> ResolvedSyncJob {
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

    private func updateJob(_ jobID: UUID, _ mutate: (inout SyncJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
    }

    private func markRunCompleted(for jobID: UUID, at date: Date) {
        updateJob(jobID) { job in
            job.lastRunDate = date
        }
    }

    private func clearError(for jobID: UUID) {
        updateJob(jobID) { job in
            job.lastErrorMessage = nil
        }
    }

    private func setError(_ message: String, for jobID: UUID) {
        guard !Self.isCancellationMessage(message) else {
            statusMessage = "Operation stopped."
            return
        }

        updateJob(jobID) { job in
            job.lastErrorMessage = message
        }
        statusMessage = message
    }

    private static func clearingCancellationErrors(from jobs: [SyncJob]) -> [SyncJob] {
        jobs.map { job in
            var copy = job
            if let message = copy.lastErrorMessage, isCancellationMessage(message) {
                copy.lastErrorMessage = nil
            }
            return copy
        }
    }

    private static func isCancellationMessage(_ message: String) -> Bool {
        message.contains("CancellationError")
    }
}
