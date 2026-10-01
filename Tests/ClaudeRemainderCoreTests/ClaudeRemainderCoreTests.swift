import ClaudeRemainderCore
import Foundation
#if canImport(XCTest)
import XCTest

final class ClaudeRemainderCoreTests: XCTestCase {
    func testDefaultProfileServiceName() {
        let profile = AccountProfile(name: "Default")
        XCTAssertEqual(profile.keychainServiceName(), "Claude Code-credentials")
    }

    func testCustomProfileServiceName() {
        let profile = AccountProfile(name: "Work", customConfigDirectory: "~/.claude-work")
        let service = profile.keychainServiceName()

        XCTAssertTrue(service.hasPrefix("Claude Code-credentials-"))
        XCTAssertEqual(service.count, "Claude Code-credentials-".count + 8)
    }

    func testCredentialReaderFileFallback() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let profile = AccountProfile(name: "Temp", customConfigDirectory: tempRoot.path)
        let credentialsURL = tempRoot.appendingPathComponent(".credentials.json")

        let content = """
        {
          "claudeAiOauth": {
            "accessToken": "abc123"
          }
        }
        """

        try content.data(using: .utf8)!.write(to: credentialsURL)

        let reader = CredentialReader()
        let credentials = reader.readCredentials(for: profile)

        XCTAssertEqual(credentials?.accessToken, "abc123")
    }

    func testParseLegacyUsageResponse() throws {
        let response: [String: Any] = [
            "five_hour": ["utilization": 40.0, "resets_at": "2026-01-01T10:00:00Z"],
            "seven_day": ["utilization": 25.0, "resets_at": "2026-01-07T10:00:00Z"]
        ]

        let windows = try UsageAPIClient.parseUsageWindows(from: response)

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.first?.label, "Session")
        XCTAssertEqual(windows.first?.remainingPercent, 60.0)
    }

    func testParseLimitsUsageResponse() throws {
        let response: [String: Any] = [
            "limits": [
                ["kind": "session", "percent": 62.0, "resets_at": "2026-01-01T10:00:00Z"],
                ["kind": "weekly_all", "percent": 30.0, "resets_at": "2026-01-07T10:00:00Z"],
                [
                    "kind": "weekly_scoped",
                    "percent": 12.0,
                    "resets_at": "2026-01-07T10:00:00Z",
                    "scope": ["model": ["display_name": "Opus"]]
                ]
            ]
        ]

        let windows = try UsageAPIClient.parseUsageWindows(from: response)

        XCTAssertTrue(windows.contains(where: { $0.label == "Session" && $0.remainingPercent == 38.0 }))
        XCTAssertTrue(windows.contains(where: { $0.label == "Weekly" && $0.remainingPercent == 70.0 }))
        XCTAssertTrue(windows.contains(where: { $0.label == "Weekly Opus" && $0.remainingPercent == 88.0 }))
    }

    func testMalformedUsageResponseFails() {
        let response: [String: Any] = ["status": "ok"]

        XCTAssertThrowsError(try UsageAPIClient.parseUsageWindows(from: response)) { error in
            XCTAssertEqual(error as? UsageFetchError, .responseMalformed)
        }
    }

    func testRefreshPolicyBackoff() {
        XCTAssertEqual(RefreshPolicy.nextRetryDelaySeconds(failureCount: 0), 30)
        XCTAssertEqual(RefreshPolicy.nextRetryDelaySeconds(failureCount: 2), 60)
        XCTAssertEqual(RefreshPolicy.nextRetryDelaySeconds(failureCount: 3), 120)
        XCTAssertEqual(RefreshPolicy.nextRetryDelaySeconds(failureCount: 5), 300)
    }

    func testSnapshotStaleness() {
        let now = Date()
        let fresh = now.addingTimeInterval(-60 * 30)
        let stale = now.addingTimeInterval(-60 * 120)

        XCTAssertFalse(RefreshPolicy.isSnapshotStale(fetchedAt: fresh, now: now))
        XCTAssertTrue(RefreshPolicy.isSnapshotStale(fetchedAt: stale, now: now))
    }
}
#else
// XCTest is unavailable in some Command Line Tools setups.
// CI still runs these tests on standard macOS runners.
#endif
