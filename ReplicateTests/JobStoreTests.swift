import XCTest
@testable import Replicate

@MainActor
final class JobStoreTests: XCTestCase {
    func testSavesAndLoadsJobs() {
        let suiteName = "ReplicateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = JobStore(defaults: defaults)
        let jobs = [
            SyncJob(
                name: "OneDrive to SMB",
                isEnabled: true,
                deleteExtraneousFiles: true,
                watchEnabled: true,
                rcloneTransferCount: 24,
                sourceBookmark: Data([1, 2, 3]),
                destinationBookmark: Data([4, 5, 6]),
                sourceDisplayPath: "/Users/me/OneDrive",
                destinationDisplayPath: "/Volumes/Share/OneDrive"
            )
        ]

        store.save(jobs)

        XCTAssertEqual(store.load(), jobs)
    }

    func testLoadsLegacyJobsWithoutTransferCount() {
        let suiteName = "ReplicateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let jobID = UUID()
        let legacyJSON = """
        [{
            "id": "\(jobID.uuidString)",
            "name": "Legacy",
            "isEnabled": true,
            "deleteExtraneousFiles": false,
            "watchEnabled": false,
            "sourceBookmark": "AQ==",
            "destinationBookmark": "Ag==",
            "sourceDisplayPath": "/source",
            "destinationDisplayPath": "/destination"
        }]
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "Replicate.SyncJobs.v1")

        let jobs = JobStore(defaults: defaults).load()

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].id, jobID)
        XCTAssertEqual(jobs[0].rcloneTransferCount, SyncJob.defaultRcloneTransferCount)
    }
}
