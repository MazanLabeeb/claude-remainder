import Foundation

extension URL {
    func expandingTildeInPath(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let path = self.path
        guard path.hasPrefix("~/") else {
            return self
        }

        let suffix = String(path.dropFirst(2))
        return homeDirectory.appendingPathComponent(suffix)
    }
}
