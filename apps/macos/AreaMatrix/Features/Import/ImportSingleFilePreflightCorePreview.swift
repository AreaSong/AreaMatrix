import Foundation

enum ImportSingleFileHasher {
    static func sha256Hex(
        for fileURL: URL,
        resourceAccess: any ImportFileResourceAccessing
    ) throws -> String {
        try resourceAccess.sha256Hex(for: fileURL)
    }
}
