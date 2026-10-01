import Foundation

public final class SnapshotStore {
    private let paths: AppPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(paths: AppPaths) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [UUID: AccountUsageSnapshot] {
        guard let data = try? Data(contentsOf: paths.snapshotsFile),
              let snapshots = try? decoder.decode([UUID: AccountUsageSnapshot].self, from: data) else {
            return [:]
        }

        return snapshots
    }

    public func save(_ snapshots: [UUID: AccountUsageSnapshot]) throws {
        let data = try encoder.encode(snapshots)
        try data.write(to: paths.snapshotsFile, options: .atomic)
    }

    public func fileSizeBytes() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: paths.snapshotsFile.path)[.size] as? UInt64) ?? 0
    }
}
