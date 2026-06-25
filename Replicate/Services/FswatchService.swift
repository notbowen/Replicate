import Foundation

enum FswatchError: LocalizedError {
    case missingExecutable
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Bundled fswatch was not found. Run Scripts/prepare-fswatch.sh and rebuild the app."
        case .launchFailed(let message):
            return message
        }
    }
}

@MainActor
final class FswatchService: FswatchServicing {
    private struct ActiveWatch {
        let process: Process
        let pipe: Pipe
        let scopedAccess: [SecurityScopedURLAccess]
    }

    private var watches: [UUID: ActiveWatch] = [:]
    private(set) var lastErrorMessage: String?

    var activeJobIDs: Set<UUID> {
        Set(watches.keys)
    }

    func configure(
        jobs: [ResolvedSyncJob],
        isPaused: Bool,
        onChange: @escaping @MainActor (UUID) -> Void
    ) {
        lastErrorMessage = nil

        if isPaused {
            stopAll()
            return
        }

        let wantedIDs = Set(jobs.map(\.job.id))
        for jobID in Array(watches.keys) where !wantedIDs.contains(jobID) {
            stop(jobID: jobID)
        }

        for resolvedJob in jobs where watches[resolvedJob.job.id] == nil {
            do {
                try start(resolvedJob, onChange: onChange)
            } catch {
                lastErrorMessage = error.localizedDescription
                stop(jobID: resolvedJob.job.id)
            }
        }
    }

    func stop(jobID: UUID) {
        guard let activeWatch = watches.removeValue(forKey: jobID) else { return }
        activeWatch.pipe.fileHandleForReading.readabilityHandler = nil
        if activeWatch.process.isRunning {
            activeWatch.process.terminate()
        }
    }

    func stopAll() {
        for jobID in Array(watches.keys) {
            stop(jobID: jobID)
        }
    }

    func executableStatusMessage() -> String? {
        bundledExecutableURL() == nil ? FswatchError.missingExecutable.localizedDescription : nil
    }

    private func start(
        _ resolvedJob: ResolvedSyncJob,
        onChange: @escaping @MainActor (UUID) -> Void
    ) throws {
        guard let executableURL = bundledExecutableURL() else {
            throw FswatchError.missingExecutable
        }

        let process = Process()
        let pipe = Pipe()
        let jobID = resolvedJob.job.id

        process.executableURL = executableURL
        process.arguments = [
            "--recursive",
            "--latency", "2",
            "--one-per-batch",
            "--print0",
            resolvedJob.sourceURL.path,
            resolvedJob.destinationURL.path
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                onChange(jobID)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw FswatchError.launchFailed("Could not launch fswatch: \(error.localizedDescription)")
        }

        watches[jobID] = ActiveWatch(
            process: process,
            pipe: pipe,
            scopedAccess: resolvedJob.scopedAccess
        )
    }

    private func bundledExecutableURL() -> URL? {
        if let url = Bundle.main.url(forResource: "fswatch", withExtension: nil, subdirectory: "Tools") {
            return url
        }

        return Bundle.main.url(forResource: "fswatch", withExtension: nil)
    }
}
