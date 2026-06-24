import Foundation

enum PendingOperation: String, Codable, CaseIterable {
    case create
    case update
    case delete
    case other

    var title: String {
        switch self {
        case .create: "Create"
        case .update: "Update"
        case .delete: "Delete"
        case .other: "Change"
        }
    }

    var systemImage: String {
        switch self {
        case .create: "plus.circle"
        case .update: "arrow.triangle.2.circlepath"
        case .delete: "trash"
        case .other: "doc"
        }
    }
}

struct PendingItem: Identifiable, Codable, Equatable {
    let id: UUID
    let jobID: UUID
    let jobName: String
    let operation: PendingOperation
    let path: String
    let itemizedCode: String

    init(
        id: UUID = UUID(),
        jobID: UUID,
        jobName: String,
        operation: PendingOperation,
        path: String,
        itemizedCode: String
    ) {
        self.id = id
        self.jobID = jobID
        self.jobName = jobName
        self.operation = operation
        self.path = path
        self.itemizedCode = itemizedCode
    }
}

enum RsyncItemizedParser {
    static func parse(_ output: String, jobID: UUID, jobName: String) -> [PendingItem] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0), jobID: jobID, jobName: jobName) }
    }

    static func parseLine(_ line: String, jobID: UUID, jobName: String) -> PendingItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2 else { return nil }

        let code = String(fields[0]).trimmingCharacters(in: .whitespaces)
        let path = String(fields[1]).trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, !path.isEmpty else { return nil }

        return PendingItem(
            jobID: jobID,
            jobName: jobName,
            operation: operation(for: code),
            path: path,
            itemizedCode: code
        )
    }

    private static func operation(for code: String) -> PendingOperation {
        if code.hasPrefix("*deleting") {
            return .delete
        }

        if code.contains("+++++++++") {
            return .create
        }

        switch code.first {
        case ">", "<", "c", "h":
            return .update
        default:
            return .other
        }
    }
}
