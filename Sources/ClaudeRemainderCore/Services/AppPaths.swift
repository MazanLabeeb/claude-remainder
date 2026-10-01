import Foundation

public struct AppPaths {
    public let root: URL

    public init(fileManager: FileManager = .default) throws {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(
            root: base.appendingPathComponent("ClaudeRemainder", isDirectory: true),
            fileManager: fileManager
        )
    }

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public var settingsFile: URL {
        root.appendingPathComponent("settings.json")
    }

    public var snapshotsFile: URL {
        root.appendingPathComponent("usage-snapshots.json")
    }
}
