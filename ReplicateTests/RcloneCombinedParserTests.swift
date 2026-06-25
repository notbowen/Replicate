import XCTest
@testable import Replicate

@MainActor
final class RcloneCombinedParserTests: XCTestCase {
    func testParsesCreateUpdateAndDeleteRowsForSyncPreview() {
        let jobID = UUID()
        let output = """
        + new.txt
        * existing.txt
        - old.txt
        = same.txt
        ignored summary line
        """

        let items = RcloneCombinedParser.parse(
            output,
            jobID: jobID,
            jobName: "Mirror",
            includeDeletes: true
        )

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.operation), [.create, .update, .delete])
        XCTAssertEqual(items.map(\.path), ["new.txt", "existing.txt", "old.txt"])
        XCTAssertTrue(items.allSatisfy { $0.jobID == jobID && $0.jobName == "Mirror" })
    }

    func testIgnoresDestinationOnlyRowsForCopyPreview() {
        let items = RcloneCombinedParser.parse(
            """
            + new.txt
            - destination-only.txt
            * changed.txt
            """,
            jobID: UUID(),
            jobName: "Mirror",
            includeDeletes: false
        )

        XCTAssertEqual(items.map(\.operation), [.create, .update])
        XCTAssertEqual(items.map(\.path), ["new.txt", "changed.txt"])
    }

    func testParsesErrorRowsAsOther() {
        let items = RcloneCombinedParser.parse(
            "! unreadable.txt",
            jobID: UUID(),
            jobName: "Mirror",
            includeDeletes: true
        )

        XCTAssertEqual(items.map(\.operation), [.other])
        XCTAssertEqual(items.map(\.path), ["unreadable.txt"])
    }
}
