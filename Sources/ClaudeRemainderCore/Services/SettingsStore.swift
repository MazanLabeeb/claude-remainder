import Foundation

public final class SettingsStore {
    private let paths: AppPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(paths: AppPaths) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: paths.settingsFile),
              let value = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings.default()
        }

        return value
    }

    public func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsFile, options: .atomic)
    }
}
