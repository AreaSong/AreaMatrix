import Foundation

protocol ImportBatchCoreFileLoading: Sendable {
    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot]
}

struct CoreBridgeBatchFileLoader: ImportBatchCoreFileLoading {
    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot] {
        let bridge = CoreBridge()
        return try await ImportBatchCoreFileLoader.load(repoPath: repoPath, categories: categories) { repoPath, filter in
            try await bridge.listFiles(repoPath: repoPath, filter: filter)
        }
    }
}

protocol ImportBatchDuplicatePrechecking: Sendable {
    func precheckDuplicates(
        repoPath: String,
        sourceURLs: [URL],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchDuplicatePrecheckResult]
}

protocol ImportBatchNameConflictPrechecking: Sendable {
    func precheckNameConflicts(
        repoPath: String,
        rows: [ImportBatchPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchNameConflictPrecheckResult]
}

struct CoreImportBatchNameConflictPrechecker: ImportBatchNameConflictPrechecking {
    private let fileLoader: any ImportBatchCoreFileLoading

    init(fileLoader: any ImportBatchCoreFileLoading = CoreBridgeBatchFileLoader()) {
        self.fileLoader = fileLoader
    }

    func precheckNameConflicts(
        repoPath: String,
        rows: [ImportBatchPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchNameConflictPrecheckResult] {
        do {
            let files = try await fileLoader.loadImportPreviewFiles(
                repoPath: repoPath,
                categories: Self.categories(for: rows, destination: destination)
            )
            return rows.reduce(into: [:]) { conflicts, row in
                let targetPath = ImportBatchPrecheckTarget.relativePath(for: row, destination: destination)
                guard let sameName = files.first(where: { $0.path == targetPath }) else { return }
                conflicts[row.id] = .conflict(existingPath: sameName.path)
            }
        } catch {
            return rows.reduce(into: [:]) { conflicts, row in
                conflicts[row.id] = .failed("Name conflict precheck failed: \(error.localizedDescription)")
            }
        }
    }

    private static func categories(
        for rows: [ImportBatchPreviewRow],
        destination: ImportBatchDestinationOption
    ) -> Set<String?> {
        switch destination {
        case .autoClassify:
            return Set(rows.map { ImportBatchPrecheckTarget.category(for: $0, destination: destination) })
        case .category, .repositoryRoot:
            return [ImportBatchPrecheckTarget.category(for: rows.first, destination: destination)]
        }
    }
}

enum ImportBatchDuplicatePrecheckResult: Equatable, Sendable {
    case duplicate(existingPath: String)
    case nameConflict(existingPath: String)
    case iCloudPlaceholder(path: String)
    case blocked(String)
    case failed(String)
}

enum ImportBatchNameConflictPrecheckResult: Equatable, Sendable {
    case conflict(existingPath: String)
    case failed(String)
}

struct CoreImportBatchDuplicatePrechecker: ImportBatchDuplicatePrechecking {
    private let fileLoader: any ImportBatchCoreFileLoading

    init(fileLoader: any ImportBatchCoreFileLoading = CoreBridgeBatchFileLoader()) {
        self.fileLoader = fileLoader
    }

    func precheckDuplicates(
        repoPath: String,
        sourceURLs: [URL],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchDuplicatePrecheckResult] {
        let placeholderResults = sourceURLs.reduce(
            into: [String: ImportBatchDuplicatePrecheckResult]()
        ) { results, sourceURL in
            if ImportSingleFilePreflightTarget.isICloudPlaceholder(sourceURL) {
                results[sourceURL.path] = .iCloudPlaceholder(path: sourceURL.path)
            }
        }
        let readableURLs = sourceURLs.filter { placeholderResults[$0.path] == nil }
        guard !readableURLs.isEmpty else { return placeholderResults }

        do {
            let files = try await fileLoader.loadImportPreviewFiles(
                repoPath: repoPath,
                categories: [nil]
            )
            return readableURLs.reduce(into: placeholderResults) { results, sourceURL in
                results[sourceURL.path] = precheckFile(sourceURL, against: files)
            }
        } catch {
            return readableURLs.reduce(into: placeholderResults) { results, sourceURL in
                results[sourceURL.path] = .failed("Duplicate precheck failed: \(error.localizedDescription)")
            }
        }
    }

    private func precheckFile(
        _ sourceURL: URL,
        against files: [FileEntrySnapshot]
    ) -> ImportBatchDuplicatePrecheckResult? {
        do {
            let sourceHash = try ImportSingleFileHasher.sha256Hex(for: sourceURL)
            guard let duplicate = files.first(where: { $0.hashSha256 == sourceHash }) else {
                return nil
            }
            return .duplicate(existingPath: duplicate.path)
        } catch {
            return .failed("Duplicate precheck failed: \(error.localizedDescription)")
        }
    }
}

enum ImportBatchCoreFileLoader {
    static func load(
        repoPath: String,
        categories: Set<String?>,
        listFiles: (String, FileFilterSnapshot) async throws -> [FileEntrySnapshot]
    ) async throws -> [FileEntrySnapshot] {
        let normalizedCategories = categories.isEmpty ? [nil] : Array(categories)
        var files: [FileEntrySnapshot] = []
        for category in normalizedCategories {
            files.append(contentsOf: try await loadCategoryFiles(
                repoPath: repoPath,
                category: category,
                listFiles: listFiles
            ))
        }
        return files
    }

    private static func loadCategoryFiles(
        repoPath: String,
        category: String?,
        listFiles: (String, FileFilterSnapshot) async throws -> [FileEntrySnapshot]
    ) async throws -> [FileEntrySnapshot] {
        var offset: Int64 = 0
        var files: [FileEntrySnapshot] = []

        while true {
            let page = try await listFiles(repoPath, FileFilterSnapshot(
                category: normalizedCategory(category),
                includeDeleted: false,
                importedAfter: nil,
                importedBefore: nil,
                limit: 200,
                offset: offset
            ))
            files.append(contentsOf: page)
            guard page.count == 200 else { return files }
            offset += 200
        }
    }

    private static func normalizedCategory(_ category: String?) -> String? {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ImportBatchPrecheckTarget {
    static func relativePath(
        for row: ImportBatchPreviewRow,
        destination: ImportBatchDestinationOption
    ) -> String {
        let filename = row.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = category(for: row, destination: destination) else {
            return filename
        }
        return "\(category)/\(filename)"
    }

    static func category(
        for row: ImportBatchPreviewRow?,
        destination: ImportBatchDestinationOption
    ) -> String? {
        switch destination {
        case .autoClassify:
            let category = row?.predictedCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "inbox"
            return category.isEmpty ? "inbox" : category
        case .category(let slug):
            return slug.trimmingCharacters(in: .whitespacesAndNewlines)
        case .repositoryRoot:
            return nil
        }
    }
}
