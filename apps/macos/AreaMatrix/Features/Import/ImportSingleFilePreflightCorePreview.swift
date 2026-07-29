import Foundation

enum ImportSingleFileHasher {
    static func sha256Hex(for fileURL: URL) throws -> String {
        try ImportPlatformServices.sha256Hex(for: fileURL)
    }
}
