import Foundation

public final class UsageAPIClient {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchUsage(accessToken: String) async throws -> UsageResponsePayload {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeRemainder/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageFetchError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageFetchError.network("Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageFetchError.unauthorized
        case 429:
            throw UsageFetchError.rateLimited
        default:
            throw UsageFetchError.network("HTTP \(httpResponse.statusCode)")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw UsageFetchError.responseMalformed
        }

        return try Self.parseUsagePayload(from: dictionary)
    }

    public static func parseUsagePayload(from response: [String: Any]) throws -> UsageResponsePayload {
        let windows = try parseUsageWindows(from: response)
        let metadata = parseMetadata(from: response)
        return UsageResponsePayload(windows: windows, metadata: metadata)
    }

    public static func parseUsageWindows(from response: [String: Any]) throws -> [UsageWindow] {
        var windows: [String: UsageWindow] = [:]

        for (key, label) in [
            ("five_hour", "Session"),
            ("seven_day", "Weekly"),
            ("seven_day_opus", "Weekly Opus"),
            ("seven_day_sonnet", "Weekly Sonnet"),
            ("seven_day_fable", "Weekly Fable")
        ] {
            guard let bucket = response[key] as? [String: Any],
                  let percent = readPercent(from: bucket),
                  let reset = readDate(from: bucket["resets_at"]) else {
                continue
            }

            windows[label] = UsageWindow(label: label, usedPercent: percent, resetsAt: reset)
        }

        if let limits = response["limits"] as? [[String: Any]] {
            for item in limits {
                guard let kind = item["kind"] as? String,
                      let percent = readPercent(from: item),
                      let reset = readDate(from: item["resets_at"]) else {
                    continue
                }

                let label: String
                switch kind {
                case "session":
                    label = "Session"
                case "weekly_all":
                    label = "Weekly"
                case "weekly_scoped":
                    if let displayName =
                        (((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String) {
                        label = "Weekly \(displayName)"
                    } else {
                        continue
                    }
                default:
                    continue
                }

                windows[label] = UsageWindow(label: label, usedPercent: percent, resetsAt: reset)
            }
        }

        let sorted = windows.values.sorted { lhs, rhs in
            sortPriority(label: lhs.label) < sortPriority(label: rhs.label)
        }

        if sorted.isEmpty {
            throw UsageFetchError.responseMalformed
        }

        return sorted
    }

    private static func parseMetadata(from response: [String: Any]) -> [UsageMetadataItem] {
        var items: [UsageMetadataItem] = []

        if let extraUsage = response["extra_usage"] as? [String: Any] {
            if let enabled = extraUsage["is_enabled"] as? Bool {
                items.append(UsageMetadataItem(key: "Overage enabled", value: enabled ? "yes" : "no"))
            }
            if let monthlyLimit = extraUsage["monthly_limit"] {
                items.append(UsageMetadataItem(key: "Overage monthly limit", value: "\(monthlyLimit)"))
            }
            if let usedCredits = extraUsage["used_credits"] {
                items.append(UsageMetadataItem(key: "Overage used credits", value: "\(usedCredits)"))
            }
            if let utilization = extraUsage["utilization"] {
                items.append(UsageMetadataItem(key: "Overage utilization", value: "\(utilization)"))
            }
        }

        if let limits = response["limits"] as? [[String: Any]] {
            let scopedCount = limits.filter { ($0["kind"] as? String) == "weekly_scoped" }.count
            if scopedCount > 0 {
                items.append(UsageMetadataItem(key: "Scoped weekly limits", value: "\(scopedCount)"))
            }
        }

        for key in ["subscription_type", "plan", "account_id", "user_id"] {
            if let value = response[key] {
                items.append(UsageMetadataItem(key: key.replacingOccurrences(of: "_", with: " ").capitalized, value: "\(value)"))
            }
        }

        return items
    }

    private static func sortPriority(label: String) -> String {
        if label == "Session" {
            return "0"
        }
        if label == "Weekly" {
            return "1"
        }
        return "2-\(label.lowercased())"
    }

    private static func readPercent(from dictionary: [String: Any]) -> Double? {
        for key in ["utilization", "percent", "used_percentage"] {
            if let number = dictionary[key] as? Double {
                return number
            }
            if let number = dictionary[key] as? NSNumber {
                return number.doubleValue
            }
            if let text = dictionary[key] as? String, let value = Double(text) {
                return value
            }
        }

        return nil
    }

    private static func readDate(from value: Any?) -> Date? {
        guard let value else {
            return nil
        }

        if let seconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let text = value as? String {
            if let seconds = TimeInterval(text) {
                return Date(timeIntervalSince1970: seconds)
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }

        return nil
    }
}
