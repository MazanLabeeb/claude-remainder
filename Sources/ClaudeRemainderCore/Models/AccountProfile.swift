import Foundation

public struct AccountProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// nil means the default Claude Code profile at ~/.claude
    public var customConfigDirectory: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        customConfigDirectory: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.customConfigDirectory = customConfigDirectory?.nilIfEmpty
        self.isEnabled = isEnabled
    }

    public var usesDefaultConfig: Bool {
        customConfigDirectory == nil
    }

    public func resolvedConfigDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let customConfigDirectory {
            return URL(fileURLWithPath: customConfigDirectory)
                .expandingTildeInPath(homeDirectory: homeDirectory)
                .standardizedFileURL
        }

        return homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL
    }

    public func keychainServiceName(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let base = "Claude Code-credentials"
        guard let customConfigDirectory else {
            return base
        }

        let resolved = URL(fileURLWithPath: customConfigDirectory)
            .expandingTildeInPath(homeDirectory: homeDirectory)
            .standardizedFileURL
            .path

        return "\(base)-\(Sha256.shortHash(of: resolved))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
