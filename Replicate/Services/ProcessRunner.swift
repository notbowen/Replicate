import Foundation

struct ProcessResult {
    let output: String
    let terminationStatus: Int32
}

enum ProcessRunnerError: LocalizedError {
    case cancelled
    case launchFailed(String)
    case failed(executable: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Operation stopped."
        case .launchFailed(let message):
            return message
        case .failed(let executable, let status, let output):
            let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "\(executable) exited with status \(status)."
            }

            return "\(executable) exited with status \(status): \(details)"
        }
    }
}

@MainActor
final class ProcessRunner {
    private var process: Process?
    private var didRequestTermination = false

    var isRunning: Bool {
        process?.isRunning == true
    }

    func run(executableURL: URL, arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        didRequestTermination = false

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        self.process = process

        do {
            try process.run()
        } catch {
            self.process = nil
            throw ProcessRunnerError.launchFailed("Could not launch \(executableURL.path): \(error.localizedDescription)")
        }

        var data = Data()
        do {
            for try await byte in outputPipe.fileHandleForReading.bytes {
                data.append(byte)
            }
        } catch {
            if process.isRunning {
                process.terminate()
            }
            self.process = nil
            if error is CancellationError || Task.isCancelled || didRequestTermination {
                throw ProcessRunnerError.cancelled
            }
            throw error
        }

        process.waitUntilExit()
        self.process = nil

        if didRequestTermination || Task.isCancelled {
            didRequestTermination = false
            throw ProcessRunnerError.cancelled
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(output: output, terminationStatus: process.terminationStatus)
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        didRequestTermination = true
        process.terminate()
    }
}
