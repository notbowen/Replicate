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
                sourceBookmark: Data([1, 2, 3]),
                destinationBookmark: Data([4, 5, 6]),
                sourceDisplayPath: "/Users/me/OneDrive",
                destinationDisplayPath: "/Volumes/Share/OneDrive"
            )
        ]

        store.save(jobs)

        XCTAssertEqual(store.load(), jobs)
    }
}
