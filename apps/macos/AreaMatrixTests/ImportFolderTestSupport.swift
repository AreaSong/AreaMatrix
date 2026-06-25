@testable import AreaMatrix
import Foundation

struct ImportFolderPredictRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor ImportFolderRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportFolderPredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportFolderPredictRequest(repoPath: repoPath, filename: filename))
        guard !results.isEmpty else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch results.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [ImportFolderPredictRequest] {
        requests
    }
}

actor ImportFolderMappedPredictor: CoreCategoryPredicting {
    private let resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportFolderPredictRequest] = []

    init(resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]) {
        self.resultsByFilename = resultsByFilename
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportFolderPredictRequest(repoPath: repoPath, filename: filename))
        guard let result = resultsByFilename[filename] else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [ImportFolderPredictRequest] {
        requests
    }
}

struct ImportFolderStaticFolderScanner: ImportFolderScanning {
    var result: ImportFolderScanResult

    func scanFolder(rootURL _: URL, includeHiddenFiles _: Bool,
                    followSymlinks _: Bool) async -> ImportFolderScanResult {
        result
    }
}

func importFolderStaticScanner(urls: [URL]) -> ImportFolderStaticFolderScanner {
    ImportFolderStaticFolderScanner(result: importFolderFolderScanResult(rows: urls.map { url in
        ImportFolderPreviewRow.loading(fileURL: url, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
    }))
}

func importFolderScanErrorScanner(readyURL: URL, cloudURL: URL) -> ImportFolderStaticFolderScanner {
    ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
        rows: importFolderPlaceholderRows(readyURL: readyURL, cloudURL: cloudURL),
        folderCount: 0,
        skippedRules: [],
        errors: [ImportFolderScanError(path: "/tmp/client-a/private", message: "Permission denied")]
    ))
}

func importFolderCleanPlaceholderScanner(readyURL: URL, cloudURL: URL) -> ImportFolderStaticFolderScanner {
    ImportFolderStaticFolderScanner(result: importFolderFolderScanResult(rows: importFolderPlaceholderRows(
        readyURL: readyURL,
        cloudURL: cloudURL
    )))
}

private func importFolderPlaceholderRows(readyURL: URL, cloudURL: URL) -> [ImportFolderPreviewRow] {
    [
        ImportFolderPreviewRow.loading(fileURL: readyURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
        ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
            .withStatus(.iCloudPlaceholder(path: cloudURL.path))
    ]
}

actor ImportFolderSequenceFolderScanner: ImportFolderScanning {
    private var results: [ImportFolderScanResult]

    init(results: [ImportFolderScanResult]) {
        self.results = results
    }

    func scanFolder(rootURL _: URL, includeHiddenFiles _: Bool,
                    followSymlinks _: Bool) async -> ImportFolderScanResult {
        guard !results.isEmpty else {
            return ImportFolderScanResult(rows: [], folderCount: 0, skippedRules: [], errors: [])
        }
        return results.removeFirst()
    }
}

actor ImportFolderRecordingICloudDownloader: ICloudPlaceholderDownloading {
    private var urls: [URL] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func downloadPlaceholder(at sourceURL: URL) async throws {
        urls.append(sourceURL)
        if let error {
            throw error
        }
    }

    func recordedURLs() -> [URL] {
        urls
    }
}

func importFolderFolderRequest(
    rootURL: URL,
    destination: ImportEntryDestination = .autoClassify,
    allowReplaceDuringImport: Bool = false,
    isTrashAvailable: Bool = true
) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: destination,
        urls: [rootURL],
        kind: .folder,
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: allowReplaceDuringImport,
        isTrashAvailable: isTrashAvailable
    )
}

struct ImportFolderConflictPrecheckRequest: Equatable {
    var repoPath: String
    var rowIDs: [String]
    var destination: ImportBatchDestinationOption
}

actor ImportFolderStaticConflictPrechecker: ImportFolderConflictPrechecking {
    private let results: [String: ImportFolderConflictPrecheckResult]
    private var requests: [ImportFolderConflictPrecheckRequest] = []

    init(results: [String: ImportFolderConflictPrecheckResult]) {
        self.results = results
    }

    func precheckFolderConflicts(
        repoPath: String,
        rows: [ImportFolderPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult] {
        requests.append(ImportFolderConflictPrecheckRequest(
            repoPath: repoPath,
            rowIDs: rows.map(\.id),
            destination: destination
        ))
        return results
    }

    func recordedRequests() -> [ImportFolderConflictPrecheckRequest] {
        requests
    }
}

actor ImportFolderNoopConflictPrechecker: ImportFolderConflictPrechecking {
    func precheckFolderConflicts(
        repoPath _: String,
        rows _: [ImportFolderPreviewRow],
        destination _: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult] {
        [:]
    }
}

func makeImportFolderTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportFolderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func importFolderLoadingRow(_ fileURL: URL) -> ImportFolderPreviewRow {
    ImportFolderPreviewRow.loading(
        fileURL: fileURL,
        rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )
}

func importFolderFolderScanResult(rows: [ImportFolderPreviewRow]) -> ImportFolderScanResult {
    ImportFolderScanResult(rows: rows, folderCount: 0, skippedRules: [], errors: [])
}

extension ClassifyResultSnapshot {
    static func importFolderPrediction(
        category: String = "docs",
        suggestedName: String = "ready.pdf"
    ) -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: category,
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: 0.9
        )
    }
}
