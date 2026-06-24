import Foundation

enum RsyncMode {
    case preview
    case sync
}

enum RsyncCommandBuilder {
    static let rsyncExecutablePath = "/usr/bin/rsync"
    static let itemizedOutFormat = "%i\t%n"

    static func arguments(
        mode: RsyncMode,
        sourceURL: URL,
        destinationURL: URL,
        deleteExtraneousFiles: Bool
    ) -> [String] {
        var arguments = [
            "-a",
            "--itemize-changes",
            "--out-format=\(itemizedOutFormat)"
        ]

        switch mode {
        case .preview:
            arguments.append("--dry-run")
        case .sync:
            arguments.append("--progress")
            arguments.append("--stats")
        }

        if deleteExtraneousFiles {
            arguments.append("--delete-delay")
        }

        arguments.append(sourcePathForContentsSync(sourceURL))
        arguments.append(destinationURL.path)
        return arguments
    }

    static func sourcePathForContentsSync(_ sourceURL: URL) -> String {
        let path = sourceURL.path
        return path.hasSuffix("/") ? path : "\(path)/"
    }
}

struct SyncRunSummary {
    let output: String
    let completedAt: Date
}

@MainActor
final class RsyncService {
    private let runner = ProcessRunner()

    var isRunning: Bool {
        runner.isRunning
    }

    func preview(_ resolvedJob: ResolvedSyncJob) async throws -> [PendingItem] {
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: RsyncCommandBuilder.rsyncExecutablePath),
            arguments: RsyncCommandBuilder.arguments(
                mode: .preview,
                sourceURL: resolvedJob.sourceURL,
                destinationURL: resolvedJob.destinationURL,
                deleteExtraneousFiles: resolvedJob.job.deleteExtraneousFiles
            )
        )

        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(
                executable: "rsync",
                status: result.terminationStatus,
                output: result.output
            )
        }

        return RsyncItemizedParser.parse(
            result.output,
            jobID: resolvedJob.job.id,
            jobName: resolvedJob.job.displayName
        )
    }

    func sync(_ resolvedJob: ResolvedSyncJob) async throws -> SyncRunSummary {
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: RsyncCommandBuilder.rsyncExecutablePath),
            arguments: RsyncCommandBuilder.arguments(
                mode: .sync,
                sourceURL: resolvedJob.sourceURL,
                destinationURL: resolvedJob.destinationURL,
                deleteExtraneousFiles: resolvedJob.job.deleteExtraneousFiles
            )
        )

        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(
                executable: "rsync",
                status: result.terminationStatus,
                output: result.output
            )
        }

        return SyncRunSummary(output: result.output, completedAt: Date())
    }

    func cancel() {
        runner.terminate()
    }
}
