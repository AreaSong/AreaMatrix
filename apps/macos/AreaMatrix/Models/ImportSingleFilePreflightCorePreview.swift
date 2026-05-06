import CryptoKit
import Foundation

extension CoreBridge: CoreImportPreviewing {
    func previewSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async throws -> ImportSingleFilePreflightResult {
        let context = try await ImportSingleFileCorePreviewContext.build(
            using: self,
            request: request
        )
        if let duplicateResult = context.duplicateResult() {
            return duplicateResult
        }
        if let nameConflictResult = context.nameConflictResult() {
            return nameConflictResult
        }
        return context.successResult()
    }
}

private struct ImportSingleFileCorePreviewContext {
    var request: ImportSingleFilePreflightRequest
    var sourceHash: String
    var sourceSizeBytes: Int64?
    var targetRelativePath: String
    var files: [FileEntrySnapshot]

    static func build(
        using bridge: CoreBridge,
        request: ImportSingleFilePreflightRequest
    ) async throws -> ImportSingleFileCorePreviewContext {
        let targetRelativePath = ImportSingleFilePreflightTarget.relativePath(
            category: request.category,
            filename: request.targetFilename
        )
        try ImportSingleFileFilenameValidator.validate(request.targetFilename)
        let sourceHash = try ImportSingleFileHasher.sha256Hex(for: request.sourceURL)
        let files = try await loadImportPreviewFiles(
            using: bridge,
            repoPath: request.repoPath,
            category: request.category
        )
        try validateImportPreviewTargetDirectory(
            repoPath: request.repoPath,
            targetRelativePath: targetRelativePath
        )
        return ImportSingleFileCorePreviewContext(
            request: request,
            sourceHash: sourceHash,
            sourceSizeBytes: importPreviewSourceFileSize(request.sourceURL),
            targetRelativePath: targetRelativePath,
            files: files
        )
    }

    func duplicateResult() -> ImportSingleFilePreflightResult? {
        guard let duplicate = files.first(where: { $0.hashSha256 == sourceHash }) else {
            return nil
        }
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            hashSha256: sourceHash,
            targetRelativePath: targetRelativePath,
            conflict: .duplicate(existingPath: duplicate.path),
            replaceOptionVisibility: conflictReplaceVisibility
        )
    }

    func nameConflictResult() -> ImportSingleFilePreflightResult? {
        guard let sameName = files.first(where: { $0.path == targetRelativePath }) else {
            return nil
        }
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            hashSha256: sourceHash,
            targetRelativePath: targetRelativePath,
            conflict: .name(path: sameName.path),
            replaceOptionVisibility: conflictReplaceVisibility
        )
    }

    func successResult() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            hashSha256: sourceHash,
            targetRelativePath: targetRelativePath,
            conflict: .none,
            replaceOptionVisibility: .hidden
        )
    }

    private var conflictReplaceVisibility: ImportSingleFileReplaceOptionVisibility {
        ImportSingleFileReplaceVisibility.resolve(
            allowReplaceDuringImport: request.allowReplaceDuringImport,
            isTrashAvailable: request.isTrashAvailable,
            hasConflict: true
        )
    }
}

private func loadImportPreviewFiles(
    using bridge: CoreBridge,
    repoPath: String,
    category: String
) async throws -> [FileEntrySnapshot] {
    let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let categoryFilter = trimmedCategory.isEmpty ? nil : trimmedCategory
    var offset: Int64 = 0
    var files: [FileEntrySnapshot] = []

    while true {
        let page = try await bridge.listFiles(repoPath: repoPath, filter: FileFilterSnapshot(
            category: categoryFilter,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: 200,
            offset: offset
        ))
        files.append(contentsOf: page)
        if page.count < 200 {
            return files
        }
        offset += 200
    }
}

private func validateImportPreviewTargetDirectory(
    repoPath: String,
    targetRelativePath: String
) throws {
    let targetURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        .appendingPathComponent(targetRelativePath)
    let targetDirectoryPath = targetURL.deletingLastPathComponent().path
    guard FileManager.default.fileExists(atPath: targetDirectoryPath) else {
        return
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: targetDirectoryPath, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw CoreError.InvalidPath(path: targetDirectoryPath)
    }
    guard FileManager.default.isWritableFile(atPath: targetDirectoryPath) else {
        throw CoreError.PermissionDenied(path: targetDirectoryPath)
    }
}

private func importPreviewSourceFileSize(_ url: URL) -> Int64? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
}

private enum ImportSingleFileReplaceVisibility {
    static func resolve(
        allowReplaceDuringImport: Bool,
        isTrashAvailable: Bool,
        hasConflict: Bool
    ) -> ImportSingleFileReplaceOptionVisibility {
        guard hasConflict else { return .hidden }
        guard allowReplaceDuringImport else { return .hidden }
        return isTrashAvailable ? .enabled : .disabled
    }
}

private enum ImportSingleFileHasher {
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
