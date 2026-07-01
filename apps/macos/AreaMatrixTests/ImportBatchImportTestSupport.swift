@testable import AreaMatrix
import Foundation

struct ImportBatchBatchImportRequest: Equatable {
    var storageMode: ImportSingleFileStorageMode = .copy
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
}

actor ImportBatchRecordingBatchImporter: CoreBatchCopyImporting {
    private var requests: [ImportBatchBatchImportRequest] = []

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        try await importBatchFile(request: CoreBatchImportRequest(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            storageMode: .copy,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: request.storageMode,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))

        let category = switch request.destination {
        case .autoClassify:
            request.suggestedCategory ?? "inbox"
        case let .category(slug):
            slug
        case .repositoryRoot:
            "__root__"
        }

        return FileEntrySnapshot.importSingleFileFixture(
            currentName: request.overrideFilename,
            category: category,
            storageMode: request.storageMode.coreStorageMode
        )
    }

    func recordedRequests() -> [ImportBatchBatchImportRequest] {
        requests
    }
}

actor ImportBatchSequenceBatchImporter: CoreBatchCopyImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [ImportBatchBatchImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: .copy,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing batch import test result")
        }
        return try results.removeFirst().get()
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: request.storageMode,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing batch import test result")
        }
        return try results.removeFirst().get()
    }

    func recordedRequests() -> [ImportBatchBatchImportRequest] {
        requests
    }
}

func importBatchInvoiceURL() -> URL {
    URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
}

func importBatchContractURL() -> URL {
    URL(fileURLWithPath: "/tmp/合同.pdf")
}

func importBatchSourcePath() -> String {
    "/tmp/source.pdf"
}

struct ImportBatchStandardBatchFixture {
    let invoiceURL: URL
    let contractURL: URL
    let request: ImportEntryRequest
    let rows: [ImportBatchPreviewRow]

    var urls: [URL] {
        [invoiceURL, contractURL]
    }
}

func importBatchStandardBatchFixture(
    destination: ImportEntryDestination = .autoClassify,
    availableCategories: [String] = ["inbox", "docs", "finance"],
    allowReplaceDuringImport: Bool = false,
    isTrashAvailable: Bool = true
) -> ImportBatchStandardBatchFixture {
    let invoiceURL = importBatchInvoiceURL()
    let contractURL = importBatchContractURL()
    return ImportBatchStandardBatchFixture(
        invoiceURL: invoiceURL,
        contractURL: contractURL,
        request: importBatchBatchRequest(
            destination: destination,
            urls: [invoiceURL, contractURL],
            availableCategories: availableCategories,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        ),
        rows: importBatchReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
    )
}

@MainActor
func importBatchCopyImportModel(
    importer: any CoreBatchCopyImporting = ImportBatchRecordingBatchImporter(),
    errorMapper: any CoreErrorMapping = RecordingCoreErrorMapper.importSingleFile()
) -> ImportBatchCopyImportModel {
    ImportBatchCopyImportModel(
        importer: importer,
        errorMapper: errorMapper
    )
}

func importBatchProgress(
    completed: Int,
    failed: Int = 0,
    total: Int = 2,
    remaining: Int? = nil,
    currentPath: String
) -> ImportBatchProgressSnapshot {
    ImportBatchProgressSnapshot(
        completed: completed,
        failed: failed,
        total: total,
        remaining: remaining ?? max(total - completed - failed, 0),
        currentPath: currentPath
    )
}

func importBatchNameConflictContractRow(
    url: URL,
    suggestedName: String = "合同.pdf",
    existingPath: String = "docs/合同.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.nameConflict(
        url: url,
        prediction: .importBatchPrediction(category: "docs", suggestedName: suggestedName, confidence: 0.82),
        existingPath: existingPath
    )
}

func importBatchDuplicateInvoiceRow(
    url: URL,
    existingPath: String = "finance/Invoice_2026Q1.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.duplicate(
        url: url,
        prediction: .importBatchPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
        existingPath: existingPath
    )
}

@MainActor
func importBatchOnboardingModel(
    opening: RepositoryOpeningResult? = nil,
    fileRevealer: (any RepositoryFileRevealing)? = nil
) -> OnboardingModel {
    switch (opening, fileRevealer) {
    case let (opening?, fileRevealer?):
        OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            fileRevealer: fileRevealer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
    case let (opening?, nil):
        OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
    case let (nil, fileRevealer?):
        OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            fileRevealer: fileRevealer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
    case (nil, nil):
        OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
    }
}

struct ImportBatchNameConflictPrecheckRequest: Equatable {
    var repoPath: String
    var rowIDs: [String]
    var destination: ImportBatchDestinationOption
}

actor ImportBatchStaticNameConflictPrechecker: ImportBatchNameConflictPrechecking {
    private let results: [String: ImportBatchNameConflictPrecheckResult]
    private var requests: [ImportBatchNameConflictPrecheckRequest] = []

    init(results: [String: ImportBatchNameConflictPrecheckResult]) {
        self.results = results
    }

    func precheckNameConflicts(
        repoPath: String,
        rows: [ImportBatchPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchNameConflictPrecheckResult] {
        requests.append(ImportBatchNameConflictPrecheckRequest(
            repoPath: repoPath,
            rowIDs: rows.map(\.id),
            destination: destination
        ))
        return results
    }

    func recordedRequests() -> [ImportBatchNameConflictPrecheckRequest] {
        requests
    }
}
