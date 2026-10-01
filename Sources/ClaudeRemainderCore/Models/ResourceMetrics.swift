import Foundation

public struct ResourceMetrics: Equatable {
    public var sampledAt: Date
    public var cpuPercent: Double
    public var residentMemoryBytes: UInt64
    public var uptimeSeconds: TimeInterval
    public var cacheBytes: UInt64
    public var networkRefreshCount: Int

    public init(
        sampledAt: Date = Date(),
        cpuPercent: Double,
        residentMemoryBytes: UInt64,
        uptimeSeconds: TimeInterval,
        cacheBytes: UInt64,
        networkRefreshCount: Int
    ) {
        self.sampledAt = sampledAt
        self.cpuPercent = cpuPercent
        self.residentMemoryBytes = residentMemoryBytes
        self.uptimeSeconds = uptimeSeconds
        self.cacheBytes = cacheBytes
        self.networkRefreshCount = networkRefreshCount
    }
}
