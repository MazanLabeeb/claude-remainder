import ClaudeRemainderCore
import Foundation
import Testing

@Test("Default profile uses base keychain service")
func defaultProfileServiceName() {
    let profile = AccountProfile(name: "Default")
    #expect(profile.keychainServiceName() == "Claude Code-credentials")
}

@Test("Custom profile appends hashed keychain suffix")
func customProfileServiceName() {
    let profile = AccountProfile(name: "Work", customConfigDirectory: "~/.claude-work")
    let service = profile.keychainServiceName()

    #expect(service.hasPrefix("Claude Code-credentials-"))
    #expect(service.count == "Claude Code-credentials-".count + 8)
}

@Test("Credential reader falls back to .credentials.json")
func credentialReaderFileFallback() throws {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.path
    let profile = AccountProfile(name: "Temp", customConfigDirectory: configPath)

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

    #expect(credentials?.accessToken == "abc123")
}

@Test("Parses legacy usage endpoint shape")
func parseLegacyUsageResponse() throws {
    let response: [String: Any] = [
        "five_hour": ["utilization": 40.0, "resets_at": "2026-01-01T10:00:00Z"],
        "seven_day": ["utilization": 25.0, "resets_at": "2026-01-07T10:00:00Z"]
    ]

    let windows = try UsageAPIClient.parseUsageWindows(from: response)

    #expect(windows.count == 2)
    #expect(windows.first?.label == "Session")
    #expect(windows.first?.remainingPercent == 60.0)
}

@Test("Parses modern limits array with scoped model")
func parseLimitsUsageResponse() throws {
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

    #expect(windows.contains(where: { $0.label == "Session" && $0.remainingPercent == 38.0 }))
    #expect(windows.contains(where: { $0.label == "Weekly" && $0.remainingPercent == 70.0 }))
    #expect(windows.contains(where: { $0.label == "Weekly Opus" && $0.remainingPercent == 88.0 }))
}

@Test("Malformed usage response fails parsing")
func malformedUsageResponseFails() {
    let response: [String: Any] = [
        "status": "ok"
    ]

    #expect(throws: UsageFetchError.self) {
        _ = try UsageAPIClient.parseUsageWindows(from: response)
    }
}

@Test("Refresh policy backoff grows with repeated failures")
func refreshPolicyBackoff() {
    #expect(RefreshPolicy.nextRetryDelaySeconds(failureCount: 0) == 30)
    #expect(RefreshPolicy.nextRetryDelaySeconds(failureCount: 2) == 60)
    #expect(RefreshPolicy.nextRetryDelaySeconds(failureCount: 3) == 120)
    #expect(RefreshPolicy.nextRetryDelaySeconds(failureCount: 5) == 300)
}

@Test("Snapshot staleness threshold is applied")
func snapshotStaleness() {
    let now = Date()
    let fresh = now.addingTimeInterval(-60 * 30)
    let stale = now.addingTimeInterval(-60 * 120)

    #expect(!RefreshPolicy.isSnapshotStale(fetchedAt: fresh, now: now))
    #expect(RefreshPolicy.isSnapshotStale(fetchedAt: stale, now: now))
}
