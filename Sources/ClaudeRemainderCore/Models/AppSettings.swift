import Foundation

public struct AppSettings: Codable, Equatable {
    public enum AutoRefreshMode: Int, Codable, CaseIterable {
        case off = 0
        case every15Minutes = 15
        case every30Minutes = 30
        case every60Minutes = 60

        public var title: String {
            switch self {
            case .off:
                return "Manual only"
            case .every15Minutes:
                return "Every 15 minutes"
            case .every30Minutes:
                return "Every 30 minutes"
            case .every60Minutes:
                return "Every 60 minutes"
            }
        }
    }

    public var profiles: [AccountProfile]
    public var autoRefreshMode: AutoRefreshMode
    public var maxConcurrentRefreshes: Int

    public init(
        profiles: [AccountProfile],
        autoRefreshMode: AutoRefreshMode = .off,
        maxConcurrentRefreshes: Int = 2
    ) {
        self.profiles = profiles
        self.autoRefreshMode = autoRefreshMode
        self.maxConcurrentRefreshes = max(1, min(maxConcurrentRefreshes, 4))
    }

    public static func `default`() -> AppSettings {
        AppSettings(
            profiles: [
                AccountProfile(name: "Default", customConfigDirectory: nil, isEnabled: true),
                AccountProfile(name: "Account 2", customConfigDirectory: "~/.claude-account-2", isEnabled: false)
            ],
            autoRefreshMode: .off,
            maxConcurrentRefreshes: 2
        )
    }
}
