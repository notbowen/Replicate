import XCTest
@testable import Replicate

@MainActor
final class RcloneCommandBuilderTests: XCTestCase {
    func testPreviewArgumentsUseCopyDryRunCombinedReportAndTransferCount() {
        let arguments = RcloneCommandBuilder.arguments(
            mode: .preview,
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            destinationURL: URL(fileURLWithPath: "/tmp/destination"),
            deleteExtraneousFiles: false,
            transferCount: 16
        )

        XCTAssertEqual(arguments, [
            "copy",
            "--config=",
            "--transfers",
            "16",
            "--dry-run",
            "--combined=-",
            "--log-level=ERROR",
            "/tmp/source",
            "/tmp/destination"
        ])
    }

    func testSyncArgumentsUseSyncWhenDeleteIsEnabled() {
        let arguments = RcloneCommandBuilder.arguments(
            mode: .sync,
            sourceURL: URL(fileURLWithPath: "/tmp/source/"),
            destinationURL: URL(fileURLWithPath: "/tmp/destination"),
            deleteExtraneousFiles: true,
            transferCount: 32
        )

        XCTAssertEqual(arguments, [
            "sync",
            "--config=",
            "--transfers",
            "32",
            "/tmp/source",
            "/tmp/destination"
        ])
    }

    func testTransferCountIsClamped() {
        let arguments = RcloneCommandBuilder.arguments(
            mode: .sync,
            sourceURL: URL(fileURLWithPath: "/tmp/source/"),
            destinationURL: URL(fileURLWithPath: "/tmp/destination"),
            deleteExtraneousFiles: true,
            transferCount: 999
        )

        XCTAssertEqual(arguments[3], "\(SyncJob.maxRcloneTransferCount)")
    }
}
