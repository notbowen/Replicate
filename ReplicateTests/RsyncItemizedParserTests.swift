import XCTest
@testable import Replicate

@MainActor
final class RsyncItemizedParserTests: XCTestCase {
    func testParsesCreateUpdateAndDeleteRows() {
        let jobID = UUID()
        let output = """
        >f+++++++++\tnew.txt
        >f..t......\texisting.txt
        *deleting\told.txt
        ignored summary line
        """

        let items = RsyncItemizedParser.parse(output, jobID: jobID, jobName: "Mirror")

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.operation), [.create, .update, .delete])
        XCTAssertEqual(items.map(\.path), ["new.txt", "existing.txt", "old.txt"])
        XCTAssertTrue(items.allSatisfy { $0.jobID == jobID && $0.jobName == "Mirror" })
    }
}
