import Foundation

struct LocalImportFolderScanner: ImportFolderScanning {
    func scanFolder(rootURL: URL, includeHiddenFiles: Bool, followSymlinks: Bool) async -> ImportFolderScanResult {
        await Task.detached(priority: .userInitiated) {
            scanFolderSync(
                rootURL: rootURL,
                includeHiddenFiles: includeHiddenFiles,
                followSymlinks: followSymlinks
            )
        }.value
    }
}

private func scanFolderSync(
    rootURL: URL,
    includeHiddenFiles: Bool,
    followSymlinks: Bool
) -> ImportFolderScanResult {
    var accumulator = ImportFolderScanAccumulator(rootURL: rootURL)
    let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: Array(LocalImportFolderScannerKeys.resourceKeys),
        options: [.skipsPackageDescendants]
    ) { url, error in
        accumulator.record(error: error, at: url)
        return true
    }

    guard let enumerator else {
        return ImportFolderScanResult(
            rows: [],
            folderCount: 0,
            skippedRules: [],
            errors: [ImportFolderScanError(path: rootURL.path, message: "无法读取文件夹")]
        )
    }

    for case let url as URL in enumerator {
        accumulator.consume(
            url: url,
            enumerator: enumerator,
            includeHiddenFiles: includeHiddenFiles,
            followSymlinks: followSymlinks
        )
    }

    return accumulator.finalResult()
}

private enum LocalImportFolderScannerKeys {
    static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
    ]
}

private struct ImportFolderScanAccumulator {
    private let rootURL: URL
    private var rows: [ImportFolderPreviewRow] = []
    private var folderCount = 0
    private var skippedCounts: [String: Int] = [:]
    private var errors: [ImportFolderScanError] = []

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    mutating func consume(
        url: URL,
        enumerator: FileManager.DirectoryEnumerator,
        includeHiddenFiles: Bool,
        followSymlinks: Bool
    ) {
        guard let values = try? url.resourceValues(forKeys: LocalImportFolderScannerKeys.resourceKeys) else {
            record(error: nil, at: url, fallbackMessage: "无法读取文件属性")
            return
        }

        if shouldSkipGeneratedDirectory(url: url, values: values, enumerator: enumerator) { return }
        if shouldSkipIgnoredPath(url: url, values: values, enumerator: enumerator) { return }
        if shouldSkipHidden(url: url, values: values, enumerator: enumerator, includeHiddenFiles: includeHiddenFiles) {
            return
        }
        if shouldSkipSymlink(url: url, values: values, enumerator: enumerator, followSymlinks: followSymlinks) {
            return
        }

        appendScannablePath(url: url, values: values)
    }

    mutating func record(error: Error?, at url: URL, fallbackMessage: String? = nil) {
        errors.append(ImportFolderScanError(
            path: url.path,
            message: fallbackMessage ?? error?.localizedDescription ?? "无法读取文件夹"
        ))
    }

    func finalResult() -> ImportFolderScanResult {
        ImportFolderScanResult(
            rows: rows.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending },
            folderCount: folderCount,
            skippedRules: skippedCounts
                .map { ImportFolderSkippedRule(label: $0.key, count: $0.value) }
                .sorted { $0.label < $1.label },
            errors: errors
        )
    }

    private mutating func appendScannablePath(url: URL, values: URLResourceValues) {
        if values.isDirectory == true {
            folderCount += 1
            return
        }

        guard values.isRegularFile == true || ImportSingleFilePreflightTarget.isICloudPlaceholder(url) else {
            return
        }

        let row = ImportFolderPreviewRow.loading(fileURL: url, rootURL: rootURL)
        rows.append(ImportSingleFilePreflightTarget.isICloudPlaceholder(url)
            ? row.withStatus(.iCloudPlaceholder(path: url.path))
            : row)
    }

    private mutating func shouldSkipGeneratedDirectory(
        url: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        guard url.lastPathComponent == ".areamatrix" else { return false }
        if values.isDirectory == true {
            enumerator.skipDescendants()
        }
        incrementSkip(".areamatrix/")
        return true
    }

    private mutating func shouldSkipIgnoredPath(
        url: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        if values.isDirectory != true {
            return skipIgnoredFile(url)
        }

        switch url.lastPathComponent {
        case ".git":
            enumerator.skipDescendants()
            incrementSkip(".git/")
            return true
        case "node_modules":
            enumerator.skipDescendants()
            incrementSkip("node_modules/")
            return true
        default:
            return false
        }
    }

    private mutating func skipIgnoredFile(_ url: URL) -> Bool {
        guard url.lastPathComponent == ".DS_Store" else { return false }
        incrementSkip(".DS_Store")
        return true
    }

    private mutating func shouldSkipHidden(
        url: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator,
        includeHiddenFiles: Bool
    ) -> Bool {
        guard !includeHiddenFiles, values.isHidden == true else { return false }
        if values.isDirectory == true {
            enumerator.skipDescendants()
        }
        incrementSkip("隐藏文件")
        return true
    }

    private mutating func shouldSkipSymlink(
        url: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator,
        followSymlinks: Bool
    ) -> Bool {
        guard !followSymlinks, values.isSymbolicLink == true else { return false }
        if values.isDirectory == true {
            enumerator.skipDescendants()
        }
        incrementSkip("符号链接")
        return true
    }

    private mutating func incrementSkip(_ label: String) {
        skippedCounts[label, default: 0] += 1
    }
}
