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
    public var hasSeenDashboardWindow: Bool
    public var defaultProfileID: UUID?
    public var showMetadataInDashboard: Bool

    public init(
        profiles: [AccountProfile],
        autoRefreshMode: AutoRefreshMode = .off,
        maxConcurrentRefreshes: Int = 2,
        hasSeenDashboardWindow: Bool = false,
        defaultProfileID: UUID? = nil,
        showMetadataInDashboard: Bool = true
    ) {
        self.profiles = profiles
        self.autoRefreshMode = autoRefreshMode
        self.maxConcurrentRefreshes = max(1, min(maxConcurrentRefreshes, 4))
        self.hasSeenDashboardWindow = hasSeenDashboardWindow
        self.defaultProfileID = defaultProfileID
        self.showMetadataInDashboard = showMetadataInDashboard
    }

    public static func `default`() -> AppSettings {
        AppSettings(
            profiles: [
                AccountProfile(name: "Default", customConfigDirectory: nil, isEnabled: true),
                AccountProfile(name: "Account 2", customConfigDirectory: "~/.claude-account-2", isEnabled: false)
            ],
            autoRefreshMode: .off,
            maxConcurrentRefreshes: 2,
            hasSeenDashboardWindow: false,
            defaultProfileID: nil,
            showMetadataInDashboard: true
        )
    }

    enum CodingKeys: String, CodingKey {
        case profiles
        case autoRefreshMode
        case maxConcurrentRefreshes
        case hasSeenDashboardWindow
        case defaultProfileID
        case showMetadataInDashboard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([AccountProfile].self, forKey: .profiles) ?? AppSettings.default().profiles
        autoRefreshMode = try container.decodeIfPresent(AutoRefreshMode.self, forKey: .autoRefreshMode) ?? .off
        maxConcurrentRefreshes = max(1, min(try container.decodeIfPresent(Int.self, forKey: .maxConcurrentRefreshes) ?? 2, 4))
        hasSeenDashboardWindow = try container.decodeIfPresent(Bool.self, forKey: .hasSeenDashboardWindow) ?? false
        defaultProfileID = try container.decodeIfPresent(UUID.self, forKey: .defaultProfileID)
        showMetadataInDashboard = try container.decodeIfPresent(Bool.self, forKey: .showMetadataInDashboard) ?? true
    }
}
