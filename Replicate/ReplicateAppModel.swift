import AppKit
import Combine
import Foundation

@MainActor
final class ReplicateAppModel: ObservableObject {
    @Published var jobs: [SyncJob] {
        didSet {
            handleJobsMutation(from: oldValue)
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

    private let store: any JobStoring
    private let rcloneService: any RcloneServicing
    private let fswatchService: any FswatchServicing
    private let resolver: any SyncJobResolving
    private let pendingRefreshDebounceNanoseconds: UInt64

    private var didStart = false
    private var queuedSyncJobIDs: Set<UUID> = []
    private var pendingRefreshRequest: PendingRefreshRequest?
    private var pendingRefreshDebounceTask: Task<Void, Never>?
    private var watchDebounceTasks: [UUID: Task<Void, Never>] = [:]

    convenience init() {
        self.init(
            store: JobStore(),
            rcloneService: RcloneService(),
            fswatchService: FswatchService(),
            resolver: BookmarkSyncJobResolver()
        )
    }

    init(
        store: any JobStoring,
        rcloneService: any RcloneServicing,
        fswatchService: any FswatchServicing,
        resolver: any SyncJobResolving,
        pendingRefreshDebounceNanoseconds: UInt64 = 400_000_000
    ) {
        self.store = store
        self.rcloneService = rcloneService
        self.fswatchService = fswatchService
        self.resolver = resolver
        self.pendingRefreshDebounceNanoseconds = pendingRefreshDebounceNanoseconds
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

    func start() {
        guard !didStart else { return }
        didStart = true
        refreshWatchers()
        requestPendingItemsRefresh(matching: nil, debounceNanoseconds: 0)
    }

    func addJob() {
        let job = SyncJob(name: "Sync Job \(jobs.count + 1)")
        jobs.append(job)
        selectedJobID = job.id
    }

    func deleteSelectedJob() {
        guard let selectedJobID else { return }
        jobs.removeAll { $0.id == selectedJobID }
        self.selectedJobID = jobs.first?.id
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
        requestPendingItemsRefresh(matching: nil, debounceNanoseconds: 0)
    }

    func syncAll() {
        let jobIDs = Set(jobs.filter(\.isEnabled).map(\.id))
        Task {
            await requestSync(jobIDs: jobIDs)
        }
    }

    func sync(jobID: UUID) {
        Task {
            await requestSync(jobIDs: [jobID])
        }
    }

    func stopSync() {
        rcloneService.cancel()
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
        } catch {
            setError(error.localizedDescription, for: jobID)
        }
    }

    private func handleJobsMutation(from oldJobs: [SyncJob]) {
        store.save(jobs)

        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }

        handleJobsChanged(from: oldJobs)
    }

    private func handleJobsChanged(from oldJobs: [SyncJob]) {
        let oldJobsByID = Self.jobsByID(oldJobs)
        let newJobsByID = Self.jobsByID(jobs)
        let removedJobIDs = Set(oldJobsByID.keys).subtracting(newJobsByID.keys)
        var stalePendingJobIDs = removedJobIDs
        var refreshJobIDs: Set<UUID> = []
        var shouldRefreshWatchers = !removedJobIDs.isEmpty

        for jobID in removedJobIDs {
            fswatchService.stop(jobID: jobID)
            watchDebounceTasks[jobID]?.cancel()
            watchDebounceTasks[jobID] = nil
        }

        for job in jobs {
            guard let oldJob = oldJobsByID[job.id] else {
                if job.isEnabled && job.isConfigured {
                    refreshJobIDs.insert(job.id)
                }

                if job.isEnabled && job.watchEnabled && job.isConfigured {
                    shouldRefreshWatchers = true
                }
                continue
            }

            if oldJob.displayName != job.displayName {
                updatePendingJobName(for: job.id, to: job.displayName)
            }

            if Self.pendingAffectingFieldsChanged(from: oldJob, to: job) {
                stalePendingJobIDs.insert(job.id)
                if job.isEnabled && job.isConfigured {
                    refreshJobIDs.insert(job.id)
                }
            }

            if !job.isEnabled || !job.isConfigured {
                stalePendingJobIDs.insert(job.id)
            }

            if Self.watcherAffectingFieldsChanged(from: oldJob, to: job) {
                shouldRefreshWatchers = true
            }
        }

        if !stalePendingJobIDs.isEmpty {
            pendingItems.removeAll { stalePendingJobIDs.contains($0.jobID) }
            updateIdleStatusFromPendingItems()
        }

        if shouldRefreshWatchers {
            refreshWatchers()
        }

        if !refreshJobIDs.isEmpty {
            requestPendingItemsRefresh(
                matching: refreshJobIDs,
                debounceNanoseconds: pendingRefreshDebounceNanoseconds
            )
        }
    }

    private func updatePendingJobName(for jobID: UUID, to jobName: String) {
        pendingItems = pendingItems.map { item in
            item.jobID == jobID ? item.withJobName(jobName) : item
        }
    }

    private func requestPendingItemsRefresh(
        matching jobIDs: Set<UUID>?,
        debounceNanoseconds: UInt64
    ) {
        if let pendingRefreshRequest {
            self.pendingRefreshRequest = pendingRefreshRequest.merging(matching: jobIDs)
        } else {
            pendingRefreshRequest = PendingRefreshRequest(matching: jobIDs)
        }
        pendingRefreshDebounceTask?.cancel()
        pendingRefreshDebounceTask = Task { [weak self] in
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }

            await self?.drainPendingItemsRefreshQueue()
        }
    }

    private func drainPendingItemsRefreshQueue() async {
        pendingRefreshDebounceTask = nil

        guard !isSyncing, !isRefreshingPendingItems else { return }
        guard let request = pendingRefreshRequest else { return }
        pendingRefreshRequest = nil

        await performPendingItemsRefresh(matching: request.jobIDs)
    }

    private func performPendingItemsRefresh(matching jobIDs: Set<UUID>?) async {
        isRefreshingPendingItems = true

        var refreshedItems: [PendingItem] = []
        let jobsToRefresh = jobs.filter { job in
            job.isEnabled && job.isConfigured && (jobIDs == nil || jobIDs?.contains(job.id) == true)
        }

        for job in jobsToRefresh {
            let signature = PendingRefreshSignature(job)

            do {
                let resolvedJob = try resolver.resolve(job)
                let items = try await rcloneService.preview(resolvedJob)

                guard
                    let currentJob = jobs.first(where: { $0.id == job.id }),
                    currentJob.isEnabled,
                    currentJob.isConfigured,
                    PendingRefreshSignature(currentJob) == signature
                else {
                    continue
                }

                refreshedItems.append(contentsOf: items.map { $0.withJobName(currentJob.displayName) })
                clearError(for: job.id)
            } catch ProcessRunnerError.cancelled {
                statusMessage = "Refresh stopped."
                isRefreshingPendingItems = false
                await operationDidFinish(updateStatusFromPendingItems: false)
                return
            } catch is CancellationError {
                statusMessage = "Refresh stopped."
                isRefreshingPendingItems = false
                await operationDidFinish(updateStatusFromPendingItems: false)
                return
            } catch {
                setError(error.localizedDescription, for: job.id)
            }
        }

        if let jobIDs {
            pendingItems.removeAll { jobIDs.contains($0.jobID) }
            pendingItems.append(contentsOf: refreshedItems)
        } else {
            pendingItems = refreshedItems
        }

        sortPendingItems()
        statusMessage = pendingItems.isEmpty ? "Ready" : pendingCountText
        isRefreshingPendingItems = false
        await operationDidFinish(updateStatusFromPendingItems: false)
    }

    private func requestSync(jobIDs: Set<UUID>) async {
        guard !jobIDs.isEmpty else { return }

        if isSyncing || isRefreshingPendingItems {
            queuedSyncJobIDs.formUnion(jobIDs)
            return
        }

        await performSync(jobIDs: jobIDs)
    }

    private func performSync(jobIDs: Set<UUID>) async {
        isSyncing = true
        statusMessage = "Syncing..."

        let jobsToSync = jobs.filter { job in
            job.isEnabled && job.isConfigured && jobIDs.contains(job.id)
        }

        for job in jobsToSync {
            do {
                let resolvedJob = try resolver.resolve(job)
                let summary = try await rcloneService.sync(resolvedJob)
                lastSyncOutput = summary.output
                if jobs.contains(where: { $0.id == job.id }) {
                    markRunCompleted(for: job.id, at: summary.completedAt)
                    clearError(for: job.id)
                }
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
        requestPendingItemsRefresh(matching: jobIDs, debounceNanoseconds: 0)
        await drainPendingItemsRefreshQueue()
        await drainQueuedSyncIfNeeded()
    }

    private func operationDidFinish(updateStatusFromPendingItems: Bool = true) async {
        if updateStatusFromPendingItems {
            updateIdleStatusFromPendingItems()
        }

        await drainQueuedSyncIfNeeded()
        await drainPendingItemsRefreshQueue()
    }

    private func drainQueuedSyncIfNeeded() async {
        guard !isSyncing, !isRefreshingPendingItems else { return }

        let queued = queuedSyncJobIDs
        queuedSyncJobIDs.removeAll()

        guard !queued.isEmpty else { return }
        await performSync(jobIDs: queued)
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
                return try resolver.resolve(job)
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
        requestPendingItemsRefresh(matching: [jobID], debounceNanoseconds: 0)
        await drainPendingItemsRefreshQueue()

        if isSyncing || isRefreshingPendingItems {
            queuedSyncJobIDs.insert(jobID)
            return
        }

        guard pendingItems.contains(where: { $0.jobID == jobID }) else { return }
        await requestSync(jobIDs: [jobID])
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

    private func sortPendingItems() {
        pendingItems.sort { lhs, rhs in
            let jobComparison = lhs.jobName.localizedStandardCompare(rhs.jobName)
            if jobComparison != .orderedSame {
                return jobComparison == .orderedAscending
            }

            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private func updateIdleStatusFromPendingItems() {
        guard !isSyncing, !isRefreshingPendingItems else { return }
        statusMessage = pendingItems.isEmpty ? "Ready" : pendingCountText
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

    private static func jobsByID(_ jobs: [SyncJob]) -> [UUID: SyncJob] {
        Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func pendingAffectingFieldsChanged(from oldJob: SyncJob, to newJob: SyncJob) -> Bool {
        oldJob.isEnabled != newJob.isEnabled ||
            oldJob.deleteExtraneousFiles != newJob.deleteExtraneousFiles ||
            oldJob.sourceBookmark != newJob.sourceBookmark ||
            oldJob.destinationBookmark != newJob.destinationBookmark
    }

    private static func watcherAffectingFieldsChanged(from oldJob: SyncJob, to newJob: SyncJob) -> Bool {
        oldJob.isEnabled != newJob.isEnabled ||
            oldJob.watchEnabled != newJob.watchEnabled ||
            oldJob.sourceBookmark != newJob.sourceBookmark ||
            oldJob.destinationBookmark != newJob.destinationBookmark
    }

#if DEBUG
    func waitForIdleForTesting() async {
        for _ in 0..<100 {
            if !isSyncing,
               !isRefreshingPendingItems,
               queuedSyncJobIDs.isEmpty,
               pendingRefreshRequest == nil,
               pendingRefreshDebounceTask == nil {
                return
            }

            await Task.yield()
        }
    }
#endif
}

private enum PendingRefreshRequest {
    case all
    case jobs(Set<UUID>)

    init(matching jobIDs: Set<UUID>?) {
        if let jobIDs {
            self = .jobs(jobIDs)
        } else {
            self = .all
        }
    }

    var jobIDs: Set<UUID>? {
        switch self {
        case .all:
            return nil
        case .jobs(let jobIDs):
            return jobIDs
        }
    }

    func merging(matching jobIDs: Set<UUID>?) -> PendingRefreshRequest {
        guard let jobIDs else { return .all }

        switch self {
        case .all:
            return .all
        case .jobs(let existingJobIDs):
            return .jobs(existingJobIDs.union(jobIDs))
        }
    }
}

private struct PendingRefreshSignature: Equatable {
    let id: UUID
    let isEnabled: Bool
    let deleteExtraneousFiles: Bool
    let sourceBookmark: Data?
    let destinationBookmark: Data?

    init(_ job: SyncJob) {
        id = job.id
        isEnabled = job.isEnabled
        deleteExtraneousFiles = job.deleteExtraneousFiles
        sourceBookmark = job.sourceBookmark
        destinationBookmark = job.destinationBookmark
    }
}
