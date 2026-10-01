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

public struct AccountUsageSnapshot: Codable, Equatable {
    public var profileID: UUID
    public var fetchedAt: Date
    public var windows: [UsageWindow]

    public init(profileID: UUID, fetchedAt: Date, windows: [UsageWindow]) {
        self.profileID = profileID
        self.fetchedAt = fetchedAt
        self.windows = windows
    }

    public func window(named label: String) -> UsageWindow? {
        windows.first { $0.label == label }
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
