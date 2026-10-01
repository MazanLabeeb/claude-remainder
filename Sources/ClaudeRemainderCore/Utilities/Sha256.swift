import CryptoKit
import Foundation

enum Sha256 {
    static func shortHash(of value: String, prefixLength: Int = 8) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let full = digest.map { String(format: "%02x", $0) }.joined()
        return String(full.prefix(prefixLength))
    }
}
