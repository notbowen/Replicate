import XCTest
@testable import Replicate

@MainActor
final class ReplicateAppModelTests: XCTestCase {
    func testStartRefreshesPendingItemsOnlyOnceWhenMultipleSurfacesAppear() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.rclone.previewResults[job.id] = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "one.txt")
        ]

        fixture.model.start()
        fixture.model.start()

        await fixture.model.waitForIdleForTesting()

        XCTAssertEqual(fixture.rclone.previewCalls, [job.id])
        XCTAssertEqual(fixture.model.pendingItems.map(\.path), ["one.txt"])
        XCTAssertEqual(fixture.fswatch.configureCallJobIDs, [Set()])
    }

    func testDisablingJobRemovesPendingItemsImmediately() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.model.pendingItems = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "stale.txt")
        ]
        fixture.model.statusMessage = fixture.model.pendingCountText

        fixture.model.jobs[0].isEnabled = false

        XCTAssertTrue(fixture.model.pendingItems.isEmpty)
        XCTAssertEqual(fixture.model.statusMessage, "Ready")

        await fixture.model.waitForIdleForTesting()

        XCTAssertTrue(fixture.rclone.previewCalls.isEmpty)
    }

    func testChangingPreviewAffectingSettingClearsAndRefreshesPendingItems() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.model.pendingItems = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "old.txt")
        ]
        fixture.rclone.previewResults[job.id] = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "fresh.txt")
        ]

        fixture.model.jobs[0].deleteExtraneousFiles = true

        XCTAssertTrue(fixture.model.pendingItems.isEmpty)

        await fixture.model.waitForIdleForTesting()

        XCTAssertEqual(fixture.rclone.previewCalls, [job.id])
        XCTAssertEqual(fixture.model.pendingItems.map(\.path), ["fresh.txt"])
        XCTAssertEqual(fixture.model.statusMessage, "1 pending item")
    }

    func testChangingTransferCountDoesNotClearOrRefreshPendingItems() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.model.pendingItems = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "file.txt")
        ]

        fixture.model.jobs[0].rcloneTransferCount = 24

        await fixture.model.waitForIdleForTesting()

        XCTAssertEqual(fixture.model.pendingItems.map(\.path), ["file.txt"])
        XCTAssertTrue(fixture.rclone.previewCalls.isEmpty)
        XCTAssertTrue(fixture.fswatch.configureCallJobIDs.isEmpty)
        XCTAssertEqual(fixture.store.jobs[0].rcloneTransferCount, 24)
    }

    func testRenamingJobUpdatesPendingItemsWithoutPreviewingAgain() async {
        let job = makeConfiguredJob(name: "Old")
        let fixture = makeFixture(jobs: [job])
        fixture.model.pendingItems = [
            makePendingItem(jobID: job.id, jobName: "Old", path: "file.txt")
        ]

        fixture.model.jobs[0].name = "New"

        await fixture.model.waitForIdleForTesting()

        XCTAssertEqual(fixture.model.pendingItems.map(\.jobName), ["New"])
        XCTAssertTrue(fixture.rclone.previewCalls.isEmpty)
        XCTAssertTrue(fixture.fswatch.configureCallJobIDs.isEmpty)
    }

    func testSyncRequestedDuringRefreshRunsAfterRefreshCompletes() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.rclone.heldPreviewJobIDs.insert(job.id)
        fixture.rclone.previewResults[job.id] = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "pending.txt")
        ]

        fixture.model.refreshPendingItems()
        await waitUntil {
            fixture.model.isRefreshingPendingItems && fixture.rclone.previewCalls == [job.id]
        }

        fixture.model.sync(jobID: job.id)
        await Task.yield()

        XCTAssertTrue(fixture.rclone.syncCalls.isEmpty)

        fixture.rclone.releasePreview(for: job.id)
        await fixture.model.waitForIdleForTesting()

        XCTAssertEqual(fixture.rclone.syncCalls, [job.id])
        XCTAssertEqual(fixture.rclone.previewCalls.count, 2)
    }

    func testStalePreviewResultDoesNotOverwriteJobChange() async {
        let job = makeConfiguredJob()
        let fixture = makeFixture(jobs: [job])
        fixture.rclone.heldPreviewJobIDs.insert(job.id)
        fixture.rclone.previewResults[job.id] = [
            makePendingItem(jobID: job.id, jobName: job.displayName, path: "stale.txt")
        ]

        fixture.model.refreshPendingItems()
        await waitUntil {
            fixture.model.isRefreshingPendingItems && fixture.rclone.previewCalls == [job.id]
        }

        fixture.model.jobs[0].isEnabled = false
        fixture.rclone.releasePreview(for: job.id)

        await fixture.model.waitForIdleForTesting()

        XCTAssertTrue(fixture.model.pendingItems.isEmpty)
        XCTAssertEqual(fixture.rclone.previewCalls, [job.id])
    }
}

private struct ModelFixture {
    let model: ReplicateAppModel
    let store: FakeJobStore
    let rclone: FakeRcloneService
    let fswatch: FakeFswatchService
    let resolver: FakeSyncJobResolver
}

private func makeFixture(jobs: [SyncJob]) -> ModelFixture {
    let store = FakeJobStore(jobs: jobs)
    let rclone = FakeRcloneService()
    let fswatch = FakeFswatchService()
    let resolver = FakeSyncJobResolver()
    let model = ReplicateAppModel(
        store: store,
        rcloneService: rclone,
        fswatchService: fswatch,
        resolver: resolver,
        pendingRefreshDebounceNanoseconds: 0
    )

    return ModelFixture(
        model: model,
        store: store,
        rclone: rclone,
        fswatch: fswatch,
        resolver: resolver
    )
}

private func makeConfiguredJob(
    id: UUID = UUID(),
    name: String = "Mirror",
    isEnabled: Bool = true,
    deleteExtraneousFiles: Bool = false,
    watchEnabled: Bool = false
) -> SyncJob {
    SyncJob(
        id: id,
        name: name,
        isEnabled: isEnabled,
        deleteExtraneousFiles: deleteExtraneousFiles,
        watchEnabled: watchEnabled,
        sourceBookmark: Data([1]),
        destinationBookmark: Data([2]),
        sourceDisplayPath: "/source",
        destinationDisplayPath: "/destination"
    )
}

private func makePendingItem(
    jobID: UUID,
    jobName: String,
    path: String
) -> PendingItem {
    PendingItem(
        jobID: jobID,
        jobName: jobName,
        operation: .update,
        path: path,
        itemizedCode: "*"
    )
}

private func waitUntil(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 {
        if condition() {
            return
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for condition", file: file, line: line)
}

private final class FakeJobStore: JobStoring {
    var jobs: [SyncJob]
    private(set) var savedJobs: [[SyncJob]] = []

    init(jobs: [SyncJob]) {
        self.jobs = jobs
    }

    func load() -> [SyncJob] {
        jobs
    }

    func save(_ jobs: [SyncJob]) {
        savedJobs.append(jobs)
        self.jobs = jobs
    }
}

private final class FakeSyncJobResolver: SyncJobResolving {
    private(set) var resolvedJobIDs: [UUID] = []
    var errors: [UUID: Error] = [:]

    func resolve(_ job: SyncJob) throws -> ResolvedSyncJob {
        resolvedJobIDs.append(job.id)

        if let error = errors[job.id] {
            throw error
        }

        return ResolvedSyncJob(
            job: job,
            sourceURL: URL(fileURLWithPath: "/source/\(job.id.uuidString)"),
            destinationURL: URL(fileURLWithPath: "/destination/\(job.id.uuidString)"),
            scopedAccess: []
        )
    }
}

private final class FakeRcloneService: RcloneServicing {
    var previewResults: [UUID: [PendingItem]] = [:]
    var previewResultQueue: [UUID: [[PendingItem]]] = [:]
    var heldPreviewJobIDs: Set<UUID> = []
    private(set) var previewCalls: [UUID] = []
    private(set) var syncCalls: [UUID] = []
    private(set) var cancelCallCount = 0
    private var previewContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isRunning: Bool {
        !previewContinuations.isEmpty
    }

    func preview(_ resolvedJob: ResolvedSyncJob) async throws -> [PendingItem] {
        let jobID = resolvedJob.job.id
        previewCalls.append(jobID)

        let result: [PendingItem]
        if var queue = previewResultQueue[jobID], !queue.isEmpty {
            result = queue.removeFirst()
            previewResultQueue[jobID] = queue
        } else {
            result = previewResults[jobID] ?? []
        }

        if heldPreviewJobIDs.contains(jobID) {
            await withCheckedContinuation { continuation in
                previewContinuations[jobID] = continuation
            }
        }

        return result
    }

    func sync(_ resolvedJob: ResolvedSyncJob) async throws -> SyncRunSummary {
        syncCalls.append(resolvedJob.job.id)
        return SyncRunSummary(
            output: "synced \(resolvedJob.job.id.uuidString)",
            completedAt: Date(timeIntervalSince1970: TimeInterval(syncCalls.count))
        )
    }

    func cancel() {
        cancelCallCount += 1
    }

    func releasePreview(for jobID: UUID) {
        heldPreviewJobIDs.remove(jobID)
        previewContinuations.removeValue(forKey: jobID)?.resume()
    }
}

private final class FakeFswatchService: FswatchServicing {
    private(set) var activeJobIDs: Set<UUID> = []
    private(set) var configureCallJobIDs: [Set<UUID>] = []
    private(set) var stoppedJobIDs: [UUID] = []
    private(set) var stopAllCallCount = 0
    var lastErrorMessage: String?
    var executableMessage: String?
    private var onChange: (@MainActor (UUID) -> Void)?

    func configure(
        jobs: [ResolvedSyncJob],
        isPaused: Bool,
        onChange: @escaping @MainActor (UUID) -> Void
    ) {
        let jobIDs = Set(jobs.map(\.job.id))
        configureCallJobIDs.append(jobIDs)
        activeJobIDs = isPaused ? [] : jobIDs
        self.onChange = onChange
    }

    func stop(jobID: UUID) {
        stoppedJobIDs.append(jobID)
        activeJobIDs.remove(jobID)
    }

    func stopAll() {
        stopAllCallCount += 1
        activeJobIDs.removeAll()
    }

    func executableStatusMessage() -> String? {
        executableMessage
    }

    func triggerChange(jobID: UUID) {
        onChange?(jobID)
    }
}
