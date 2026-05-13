@testable import AreaMatrix
import Foundation

struct S119PredictRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor S119RecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [S119PredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(S119PredictRequest(repoPath: repoPath, filename: filename))
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

    func recordedRequests() -> [S119PredictRequest] {
        requests
    }
}

actor S119MappedPredictor: CoreCategoryPredicting {
    private let resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]
    private var requests: [S119PredictRequest] = []

    init(resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]) {
        self.resultsByFilename = resultsByFilename
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(S119PredictRequest(repoPath: repoPath, filename: filename))
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

    func recordedRequests() -> [S119PredictRequest] {
        requests
    }
}

struct S119StaticFolderScanner: ImportFolderScanning {
    var result: ImportFolderScanResult

    func scanFolder(rootURL _: URL, includeHiddenFiles _: Bool,
                    followSymlinks _: Bool) async -> ImportFolderScanResult {
        result
    }
}

func s119StaticScanner(urls: [URL]) -> S119StaticFolderScanner {
    S119StaticFolderScanner(result: s119FolderScanResult(rows: urls.map { url in
        ImportFolderPreviewRow.loading(fileURL: url, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
    }))
}

func s119ScanErrorScanner(readyURL: URL, cloudURL: URL) -> S119StaticFolderScanner {
    S119StaticFolderScanner(result: ImportFolderScanResult(
        rows: s119PlaceholderRows(readyURL: readyURL, cloudURL: cloudURL),
        folderCount: 0,
        skippedRules: [],
        errors: [ImportFolderScanError(path: "/tmp/client-a/private", message: "Permission denied")]
    ))
}

func s119CleanPlaceholderScanner(readyURL: URL, cloudURL: URL) -> S119StaticFolderScanner {
    S119StaticFolderScanner(result: s119FolderScanResult(rows: s119PlaceholderRows(
        readyURL: readyURL,
        cloudURL: cloudURL
    )))
}

private func s119PlaceholderRows(readyURL: URL, cloudURL: URL) -> [ImportFolderPreviewRow] {
    [
        ImportFolderPreviewRow.loading(fileURL: readyURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
        ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
            .withStatus(.iCloudPlaceholder(path: cloudURL.path))
    ]
}

actor S119SequenceFolderScanner: ImportFolderScanning {
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

actor S119RecordingICloudDownloader: ICloudPlaceholderDownloading {
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

func s119FolderRequest(
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

struct S119ConflictPrecheckRequest: Equatable {
    var repoPath: String
    var rowIDs: [String]
    var destination: ImportBatchDestinationOption
}

actor S119StaticConflictPrechecker: ImportFolderConflictPrechecking {
    private let results: [String: ImportFolderConflictPrecheckResult]
    private var requests: [S119ConflictPrecheckRequest] = []

    init(results: [String: ImportFolderConflictPrecheckResult]) {
        self.results = results
    }

    func precheckFolderConflicts(
        repoPath: String,
        rows: [ImportFolderPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult] {
        requests.append(S119ConflictPrecheckRequest(
            repoPath: repoPath,
            rowIDs: rows.map(\.id),
            destination: destination
        ))
        return results
    }

    func recordedRequests() -> [S119ConflictPrecheckRequest] {
        requests
    }
}

actor S119NoopConflictPrechecker: ImportFolderConflictPrechecking {
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

func s119LoadingRow(_ fileURL: URL) -> ImportFolderPreviewRow {
    ImportFolderPreviewRow.loading(
        fileURL: fileURL,
        rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )
}

func s119FolderScanResult(rows: [ImportFolderPreviewRow]) -> ImportFolderScanResult {
    ImportFolderScanResult(rows: rows, folderCount: 0, skippedRules: [], errors: [])
}

extension ClassifyResultSnapshot {
    static func s119Prediction(
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
