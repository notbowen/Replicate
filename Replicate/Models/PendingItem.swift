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

    func withJobName(_ jobName: String) -> PendingItem {
        PendingItem(
            id: id,
            jobID: jobID,
            jobName: jobName,
            operation: operation,
            path: path,
            itemizedCode: itemizedCode
        )
    }
}

enum RcloneCombinedParser {
    static func parse(
        _ output: String,
        jobID: UUID,
        jobName: String,
        includeDeletes: Bool
    ) -> [PendingItem] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap {
                parseLine(
                    String($0),
                    jobID: jobID,
                    jobName: jobName,
                    includeDeletes: includeDeletes
                )
            }
    }

    static func parseLine(
        _ line: String,
        jobID: UUID,
        jobName: String,
        includeDeletes: Bool
    ) -> PendingItem? {
        guard line.count >= 3 else { return nil }

        let code = String(line[line.startIndex])
        let separatorIndex = line.index(after: line.startIndex)
        guard line[separatorIndex] == " " else { return nil }

        let pathStartIndex = line.index(after: separatorIndex)
        let path = String(line[pathStartIndex...])
        guard !path.isEmpty else { return nil }

        guard let operation = operation(for: code, includeDeletes: includeDeletes) else {
            return nil
        }

        return PendingItem(
            jobID: jobID,
            jobName: jobName,
            operation: operation,
            path: path,
            itemizedCode: code
        )
    }

    private static func operation(for code: String, includeDeletes: Bool) -> PendingOperation? {
        switch code {
        case "+":
            return .create
        case "*":
            return .update
        case "-":
            return includeDeletes ? .delete : nil
        case "!":
            return .other
        default:
            return nil
        }
    }
}
