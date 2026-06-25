import Foundation

enum RcloneMode {
    case preview
    case sync
}

enum RcloneCommandBuilder {
    static func arguments(
        mode: RcloneMode,
        sourceURL: URL,
        destinationURL: URL,
        deleteExtraneousFiles: Bool,
        transferCount: Int
    ) -> [String] {
        let command = deleteExtraneousFiles ? "sync" : "copy"
        var arguments = [
            command,
            "--config=",
            "--transfers",
            "\(SyncJob.clampedRcloneTransferCount(transferCount))"
        ]

        switch mode {
        case .preview:
            arguments.append("--dry-run")
            arguments.append("--combined=-")
            arguments.append("--log-level=ERROR")
        case .sync:
            break
        }

        arguments.append(sourceURL.path)
        arguments.append(destinationURL.path)
        return arguments
    }
}

enum RcloneServiceError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Bundled rclone was not found. Run Scripts/prepare-rclone.sh and rebuild the app."
        }
    }
}

struct SyncRunSummary {
    let output: String
    let completedAt: Date
}

@MainActor
final class RcloneService: RcloneServicing {
    private let runner = ProcessRunner()

    var isRunning: Bool {
        runner.isRunning
    }

    func preview(_ resolvedJob: ResolvedSyncJob) async throws -> [PendingItem] {
        guard let executableURL = Self.bundledExecutableURL() else {
            throw RcloneServiceError.missingExecutable
        }

        let result = try await runner.run(
            executableURL: executableURL,
            arguments: RcloneCommandBuilder.arguments(
                mode: .preview,
                sourceURL: resolvedJob.sourceURL,
                destinationURL: resolvedJob.destinationURL,
                deleteExtraneousFiles: resolvedJob.job.deleteExtraneousFiles,
                transferCount: resolvedJob.job.rcloneTransferCount
            )
        )

        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(
                executable: "rclone",
                status: result.terminationStatus,
                output: result.output
            )
        }

        return RcloneCombinedParser.parse(
            result.output,
            jobID: resolvedJob.job.id,
            jobName: resolvedJob.job.displayName,
            includeDeletes: resolvedJob.job.deleteExtraneousFiles
        )
    }

    func sync(_ resolvedJob: ResolvedSyncJob) async throws -> SyncRunSummary {
        guard let executableURL = Self.bundledExecutableURL() else {
            throw RcloneServiceError.missingExecutable
        }

        let result = try await runner.run(
            executableURL: executableURL,
            arguments: RcloneCommandBuilder.arguments(
                mode: .sync,
                sourceURL: resolvedJob.sourceURL,
                destinationURL: resolvedJob.destinationURL,
                deleteExtraneousFiles: resolvedJob.job.deleteExtraneousFiles,
                transferCount: resolvedJob.job.rcloneTransferCount
            )
        )

        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(
                executable: "rclone",
                status: result.terminationStatus,
                output: result.output
            )
        }

        return SyncRunSummary(output: result.output, completedAt: Date())
    }

    func cancel() {
        runner.terminate()
    }

    private static func bundledExecutableURL() -> URL? {
        if let url = Bundle.main.url(forResource: "rclone", withExtension: nil, subdirectory: "Tools") {
            return url
        }

        return Bundle.main.url(forResource: "rclone", withExtension: nil)
    }
}
