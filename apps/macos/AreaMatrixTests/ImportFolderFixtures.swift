@testable import AreaMatrix
import Foundation

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
        suggestedName: String = "ready.pdf",
        reason: ClassifyReasonSnapshot = .keyword,
        confidence: Float = 0.9
    ) -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: category,
            suggestedName: suggestedName,
            reason: reason,
            confidence: confidence
        )
    }
}
