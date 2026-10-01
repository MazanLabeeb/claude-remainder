import Foundation

public struct UsageWindow: Codable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date

    public init(label: String, usedPercent: Double, resetsAt: Date) {
        self.label = label
        self.usedPercent = Self.clampedPercent(usedPercent)
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

public struct UsageMetadataItem: Codable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct UsageResponsePayload: Equatable {
    public var windows: [UsageWindow]
    public var metadata: [UsageMetadataItem]

    public init(windows: [UsageWindow], metadata: [UsageMetadataItem]) {
        self.windows = windows
        self.metadata = metadata
    }
}

public struct AccountUsageSnapshot: Codable, Equatable {
    public var profileID: UUID
    public var fetchedAt: Date
    public var windows: [UsageWindow]
    public var metadata: [UsageMetadataItem]

    public init(
        profileID: UUID,
        fetchedAt: Date,
        windows: [UsageWindow],
        metadata: [UsageMetadataItem] = []
    ) {
        self.profileID = profileID
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.metadata = metadata
    }

    public func window(named label: String) -> UsageWindow? {
        windows.first { $0.label == label }
    }

    enum CodingKeys: String, CodingKey {
        case profileID
        case fetchedAt
        case windows
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        windows = try container.decode([UsageWindow].self, forKey: .windows)
        metadata = try container.decodeIfPresent([UsageMetadataItem].self, forKey: .metadata) ?? []
    }
}

public enum UsageFetchError: Error, LocalizedError, Equatable {
    case missingCredentials
    case unauthorized
    case rateLimited
    case responseMalformed
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Login required"
        case .unauthorized:
            return "Credentials expired or invalid"
        case .rateLimited:
            return "Rate limited by usage endpoint"
        case .responseMalformed:
            return "Unexpected usage response"
        case .network(let details):
            return details
        }
    }
}

public struct AccountUsageState: Equatable {
    public enum Status: Equatable {
        case idle
        case loading
        case fresh
        case stale
        case error(String)
    }

    public var status: Status
    public var lastError: UsageFetchError?

    public init(status: Status = .idle, lastError: UsageFetchError? = nil) {
        self.status = status
        self.lastError = lastError
    }
}
