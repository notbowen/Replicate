import Foundation

final class JobStore {
    private let defaults: UserDefaults
    private let key = "Replicate.SyncJobs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SyncJob] {
        guard let data = defaults.data(forKey: key) else { return [] }

        do {
            return try JSONDecoder().decode([SyncJob].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ jobs: [SyncJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        defaults.set(data, forKey: key)
    }
}
