import AreaMatrixFeatureIngestion
import CryptoKit
import Foundation

struct LocalImportFileResourceAccess: ImportFileResourceAccessing {
    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isICloudPlaceholder(_ url: URL) -> Bool {
        if url.path.hasSuffix(".icloud") || url.path.contains(".icloud/") {
            return true
        }
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else {
            return false
        }
        return values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    func fileSizeBytes(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ImportPlatformServices {
    static var folderScanner: any ImportFolderScanning {
        LocalImportFolderScanner()
    }

    static var fileResourceAccess: any ImportFileResourceAccessing {
        LocalImportFileResourceAccess()
    }

    static var sourcePreflightInspector: any SourcePreflightInspecting {
        LocalSourcePreflightInspector()
    }

    static func isDirectory(_ url: URL) -> Bool {
        fileResourceAccess.isDirectory(url)
    }

    static func isICloudPlaceholder(_ url: URL) -> Bool {
        fileResourceAccess.isICloudPlaceholder(url)
    }

    static func fileSizeBytes(_ url: URL) -> Int64? {
        fileResourceAccess.fileSizeBytes(url)
    }

    static func sha256Hex(for fileURL: URL) throws -> String {
        try fileResourceAccess.sha256Hex(for: fileURL)
    }
}

struct LocalSourcePreflightInspector: SourcePreflightInspecting {
    func inspect(sourceURL: URL) throws -> SourcePreflightSnapshot {
        if ImportPlatformServices.isICloudPlaceholder(sourceURL) {
            throw ImportSingleFilePreflightError(
                .iCloudPlaceholder(path: sourceURL.path),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable(L10n.display("import.source.disappeared")),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable(L10n.display("import.source.unreadable")),
                sourceSizeBytes: nil
            )
        }
        let values = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable(L10n.display("import.source.singleFileOnly")),
                sourceSizeBytes: nil
            )
        }
        return SourcePreflightSnapshot(
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate.map { Int64($0.timeIntervalSince1970) }
        )
    }
}

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
            errors: [ImportFolderScanError(
                path: rootURL.path,
                message: L10n.string("import.folder.unreadable")
            )]
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
        .ubiquitousItemDownloadingStatusKey
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
            record(error: nil, at: url, fallbackMessage: L10n.string("import.folder.attributesUnreadable"))
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
            message: fallbackMessage ?? error?.localizedDescription ?? L10n.string("import.folder.unreadable")
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

        guard values.isRegularFile == true || ImportPlatformServices.isICloudPlaceholder(url) else {
            return
        }

        let row = ImportFolderPreviewRow.loading(
            fileURL: url,
            rootURL: rootURL,
            sizeBytes: ImportPlatformServices.fileSizeBytes(url)
        )
        rows.append(ImportPlatformServices.isICloudPlaceholder(url)
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
        url _: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator,
        includeHiddenFiles: Bool
    ) -> Bool {
        guard !includeHiddenFiles, values.isHidden == true else { return false }
        if values.isDirectory == true {
            enumerator.skipDescendants()
        }
        incrementSkip(L10n.string("import.folder.hiddenFiles"))
        return true
    }

    private mutating func shouldSkipSymlink(
        url _: URL,
        values: URLResourceValues,
        enumerator: FileManager.DirectoryEnumerator,
        followSymlinks: Bool
    ) -> Bool {
        guard !followSymlinks, values.isSymbolicLink == true else { return false }
        if values.isDirectory == true {
            enumerator.skipDescendants()
        }
        incrementSkip(L10n.string("import.folder.symbolicLinks"))
        return true
    }

    private mutating func incrementSkip(_ label: String) {
        skippedCounts[label, default: 0] += 1
    }
}
