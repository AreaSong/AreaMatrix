import CryptoKit
import Foundation

protocol ImportBatchDuplicatePrechecking: Sendable {
    func precheckDuplicates(
        repoPath: String,
        sourceURLs: [URL]
    ) async -> [String: ImportBatchDuplicatePrecheckResult]
}

enum ImportBatchDuplicatePrecheckResult: Equatable, Sendable {
    case duplicate(existingPath: String)
    case failed(String)
}

struct CoreImportBatchDuplicatePrechecker: ImportBatchDuplicatePrechecking {
    private let fileLister: any CoreFileListing

    init(fileLister: any CoreFileListing = CoreBridge()) {
        self.fileLister = fileLister
    }

    func precheckDuplicates(
        repoPath: String,
        sourceURLs: [URL]
    ) async -> [String: ImportBatchDuplicatePrecheckResult] {
        do {
            let existingHashes = try await loadExistingHashes(repoPath: repoPath)
            return sourceURLs.reduce(into: [:]) { results, sourceURL in
                results[sourceURL.path] = duplicateResult(for: sourceURL, existingHashes: existingHashes)
            }
        } catch {
            return sourceURLs.reduce(into: [:]) { results, sourceURL in
                results[sourceURL.path] = .failed(Self.precheckMessage(for: error))
            }
        }
    }

    private func duplicateResult(
        for sourceURL: URL,
        existingHashes: [String: String]
    ) -> ImportBatchDuplicatePrecheckResult? {
        do {
            let sourceHash = try ImportBatchPreviewHasher.sha256Hex(for: sourceURL)
            guard let existingPath = existingHashes[sourceHash] else { return nil }
            return .duplicate(existingPath: existingPath)
        } catch {
            return .failed(Self.precheckMessage(for: error))
        }
    }

    private func loadExistingHashes(repoPath: String) async throws -> [String: String] {
        var offset: Int64 = 0
        var hashes: [String: String] = [:]

        while true {
            let page = try await fileLister.listFiles(repoPath: repoPath, filter: FileFilterSnapshot(
                category: nil,
                includeDeleted: false,
                importedAfter: nil,
                importedBefore: nil,
                limit: 200,
                offset: offset
            ))
            for file in page where !file.hashSha256.isEmpty {
                hashes[file.hashSha256] = file.path
            }
            if page.count < 200 {
                return hashes
            }
            offset += 200
        }
    }

    private static func precheckMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "重复检测失败：\(error.localizedDescription)"
        }

        switch coreError {
        case .PermissionDenied(let path):
            return "重复检测无法读取路径：\(path)"
        case .Io(let message):
            return "重复检测文件读取失败：\(message)"
        case .Db(let message):
            return "重复检测数据库读取失败：\(message)"
        default:
            return "重复检测失败：\(coreError.localizedDescription)"
        }
    }
}

private enum ImportBatchPreviewHasher {
    static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 64 * 1024)
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
