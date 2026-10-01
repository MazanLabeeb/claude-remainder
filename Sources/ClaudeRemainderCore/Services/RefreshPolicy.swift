import Foundation

public enum RefreshPolicy {
    public static func nextRetryDelaySeconds(failureCount: Int) -> TimeInterval {
        switch failureCount {
        case 0...1:
            return 30
        case 2:
            return 60
        case 3:
            return 120
        default:
            return 300
        }
    }

    public static func isSnapshotStale(
        fetchedAt: Date,
        now: Date = Date(),
        staleAfter: TimeInterval = 60 * 90
    ) -> Bool {
        now.timeIntervalSince(fetchedAt) > staleAfter
    }
}
