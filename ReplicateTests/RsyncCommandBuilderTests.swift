import XCTest
@testable import Replicate

@MainActor
final class RsyncCommandBuilderTests: XCTestCase {
    func testPreviewArgumentsUseDryRunAndTrailingSourceSlash() {
        let arguments = RsyncCommandBuilder.arguments(
            mode: .preview,
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            destinationURL: URL(fileURLWithPath: "/tmp/destination"),
            deleteExtraneousFiles: false
        )

        XCTAssertEqual(arguments, [
            "-a",
            "--itemize-changes",
            "--out-format=%i\t%n",
            "--dry-run",
            "/tmp/source/",
            "/tmp/destination"
        ])
    }

    func testSyncArgumentsIncludeDeleteWhenEnabled() {
        let arguments = RsyncCommandBuilder.arguments(
            mode: .sync,
            sourceURL: URL(fileURLWithPath: "/tmp/source/"),
            destinationURL: URL(fileURLWithPath: "/tmp/destination"),
            deleteExtraneousFiles: true
        )

        XCTAssertTrue(arguments.contains("--progress"))
        XCTAssertTrue(arguments.contains("--stats"))
        XCTAssertTrue(arguments.contains("--delete-delay"))
        XCTAssertEqual(arguments.suffix(2), ["/tmp/source/", "/tmp/destination"])
    }
}
