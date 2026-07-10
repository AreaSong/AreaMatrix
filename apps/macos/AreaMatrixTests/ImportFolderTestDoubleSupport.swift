@testable import AreaMatrix
import Foundation
import XCTest

typealias ImportFolderPredictRequest = CategoryPredictionRequest
typealias ImportFolderRecordingPredictor = RecordingCategoryPredictor
typealias ImportFolderMappedPredictor = MappedCategoryPredictor
typealias ImportFolderRecordingICloudDownloader = RecordingICloudPlaceholderDownloader

struct ImportFolderStaticFolderScanner: ImportFolderScanning {
    var result: ImportFolderScanResult

    func scanFolder(rootURL _: URL, includeHiddenFiles _: Bool,
                    followSymlinks _: Bool) async -> ImportFolderScanResult {
        result
    }
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

    func assertRecordedPrecheckDestinations(
        _ expectedDestinations: [ImportBatchDestinationOption],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.destination), expectedDestinations, file: file, line: line)
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
