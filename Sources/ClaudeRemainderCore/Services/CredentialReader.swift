import Foundation
import Security

public struct OAuthCredentials: Equatable {
    public var accessToken: String
    public var email: String?

    public init(accessToken: String, email: String? = nil) {
        self.accessToken = accessToken
        self.email = email
    }
}

/// Reads Claude Code credentials and caches them in memory, so the Keychain
/// (and its macOS access prompt) is only hit when a token is missing or rejected.
public final class CredentialReader: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: OAuthCredentials] = [:]

    public init() {}

    public func readCredentials(for profile: AccountProfile, forceReload: Bool = false) -> OAuthCredentials? {
        let cacheKey = profile.keychainServiceName()

        if !forceReload, let cached = cachedCredentials(forKey: cacheKey) {
            return cached
        }

        let credentials = readFromKeychain(profile: profile) ?? readFromFile(profile: profile)

        lock.lock()
        cache[cacheKey] = credentials
        lock.unlock()

        return credentials
    }

    /// Returns cached credentials without touching the Keychain.
    public func cachedCredentials(for profile: AccountProfile) -> OAuthCredentials? {
        cachedCredentials(forKey: profile.keychainServiceName())
    }

    private func cachedCredentials(forKey key: String) -> OAuthCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func readFromKeychain(profile: AccountProfile) -> OAuthCredentials? {
        let service = profile.keychainServiceName()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return Self.parseCredentialData(data)
    }

    private func readFromFile(profile: AccountProfile) -> OAuthCredentials? {
        let fileURL = profile
            .resolvedConfigDirectory()
            .appendingPathComponent(".credentials.json")

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return Self.parseCredentialData(data)
    }

    private static func parseCredentialData(_ data: Data) -> OAuthCredentials? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let token = extractAccessToken(from: dictionary) else {
            return nil
        }

        return OAuthCredentials(accessToken: token, email: extractEmail(from: dictionary))
    }

    private static func extractAccessToken(from dictionary: [String: Any]) -> String? {
        let keyPaths: [[String]] = [
            ["accessToken"],
            ["access_token"],
            ["claudeAiOauth", "accessToken"],
            ["claudeAiOauth", "access_token"],
            ["oauth", "accessToken"],
            ["oauth", "access_token"]
        ]

        for keyPath in keyPaths {
            if let value = value(for: keyPath, in: dictionary) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        return nil
    }

    private static func value(for keyPath: [String], in dictionary: [String: Any]) -> Any? {
        var current: Any = dictionary
        for key in keyPath {
            guard let next = (current as? [String: Any])?[key] else {
                return nil
            }
            current = next
        }

        return current
    }

    private static func extractEmail(from dictionary: [String: Any]) -> String? {
        let keyPaths: [[String]] = [
            ["email"],
            ["accountEmail"],
            ["claudeAiOauth", "email"],
            ["claudeAiOauth", "account", "email"],
            ["claudeAiOauth", "user", "email"],
            ["oauth", "email"],
            ["oauth", "user", "email"],
            ["user", "email"]
        ]

        for keyPath in keyPaths {
            if let value = value(for: keyPath, in: dictionary) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("@"), !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }
}
