@testable import AreaMatrix
import Foundation

func makeRepairTemporaryAdoptRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExisting-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct RepairStaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    func configuredRepoPath() -> String? {
        repoPath
    }
}

final class RepairRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

actor RepairRecordingConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot
    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

enum RepairRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor RepairRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: RepairRecordingRepositoryOpenResult
    private var paths: [String] = []

    init(result: RepairRecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        paths.append(repoPath)
        switch result {
        case let .success(opening):
            return opening
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

actor RepairRecordingPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot
    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

actor RepairSequencePathValidator: CoreRepositoryPathValidating {
    private var validations: [RepoPathValidationSnapshot]

    init(validations: [RepoPathValidationSnapshot]) {
        self.validations = validations
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        guard !validations.isEmpty else {
            throw CoreError.Config(reason: "missing validation fixture")
        }

        return validations.removeFirst()
    }
}

actor RepairRecordingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
    }

    func createdRepoPaths() -> [String] {
        createdPaths
    }

    func adoptedRepoPaths() -> [String] {
        adoptedPaths
    }
}

actor RepairPausingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var didStart = false

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func createdRepoPaths() -> [String] {
        createdPaths
    }
}

actor RepairStaticStartupRecoverer: CoreStartupRecovering {
    func recoverOnStartup(repoPath _: String) async throws -> RecoveryReportSnapshot {
        RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }
}

struct RepairExistingRepoMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

struct RepairNoopWelcomeHelpOpener: WelcomeHelpOpening { func openWelcomeHelp() throws {} }

extension RepoConfigSnapshot {
    static func repairFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension RepositoryOpeningResult {
    static func repairFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .repairFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

extension RepoPathValidationSnapshot {
    static func repairFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}

extension TagSetSnapshot {
    static func s207Fixture(fileID: Int64, values: [String]) -> TagSetSnapshot {
        let tags = values.map { value in
            TagRecordSnapshot(
                value: value,
                label: value,
                fileCount: 1,
                selected: true,
                disabled: false,
                updatedAt: 1_700_000_300
            )
        }
        return TagSetSnapshot(
            fileID: fileID,
            fileTags: tags,
            availableTags: tags,
            recentTags: tags,
            updatedAt: 1_700_000_300
        )
    }

    static func s208RegistryFixture(fileID: Int64) -> TagSetSnapshot {
        TagSetSnapshot(
            fileID: fileID,
            fileTags: [],
            availableTags: [
                TagRecordSnapshot(
                    value: "finance",
                    label: "Finance",
                    fileCount: 24,
                    selected: false,
                    disabled: false,
                    updatedAt: 1_700_000_300
                ),
                TagRecordSnapshot(
                    value: "legal",
                    label: "Legal",
                    fileCount: 5,
                    selected: false,
                    disabled: false,
                    updatedAt: 1_700_000_301
                )
            ],
            recentTags: [],
            updatedAt: 1_700_000_301
        )
    }
}

extension TagSuggestionReportSnapshot {
    static func s223Fixture(fileID: Int64, existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: fileID,
            suggestions: [
                TagSuggestionSnapshot(
                    suggestionID: "s223-finance",
                    slug: "finance",
                    displayName: "Finance",
                    reason: "Matched file name: invoice_2026.pdf",
                    source: .fileName,
                    matchStrength: .strong,
                    alreadyExists: false,
                    needsCreate: false,
                    status: .newTag,
                    selectedByDefault: true,
                    disabledReason: nil
                ),
                TagSuggestionSnapshot(
                    suggestionID: "s223-tax",
                    slug: "tax",
                    displayName: "Tax",
                    reason: "Matched path: finance/tax",
                    source: .path,
                    matchStrength: .weak,
                    alreadyExists: false,
                    needsCreate: true,
                    status: .newTag,
                    selectedByDefault: false,
                    disabledReason: nil
                )
            ],
            tagSet: .s207Fixture(fileID: fileID, values: existingValues),
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }

    static func s223EmptyFixture(fileID: Int64, existingValues: [String] = []) -> TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: fileID,
            suggestions: [],
            tagSet: .s207Fixture(fileID: fileID, values: existingValues),
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }
}

extension TagSuggestionApplyReportSnapshot {
    static func s223Applied(
        fileID: Int64,
        suggestionID: String = "s223-finance",
        slug: String = "finance",
        displayName _: String = "Finance"
    ) -> TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: fileID,
            requestedCount: 1,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: suggestionID,
                    slug: slug,
                    status: .applied,
                    error: nil
                )
            ],
            tagSet: .s207Fixture(fileID: fileID, values: [slug]),
            undoToken: "undo-s223",
            refreshTargets: ["tags", "change_log", "undo_actions"]
        )
    }

    static func s223PartialFailure(fileID: Int64) -> TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: fileID,
            requestedCount: 2,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 1,
            itemResults: [
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: "s223-finance",
                    slug: "finance",
                    status: .applied,
                    error: nil
                ),
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: "s223-tax",
                    slug: "tax-review",
                    status: .failed,
                    error: "Tag relation write failed."
                )
            ],
            tagSet: .s207Fixture(fileID: fileID, values: ["finance"]),
            undoToken: "undo-s223-partial",
            refreshTargets: ["tags", "change_log", "undo_actions"]
        )
    }
}

extension ChangeLogEntrySnapshot {
    static func s223Applied() -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: 223,
            fileID: 224,
            filename: "invoice_2026.pdf",
            category: "finance",
            action: "tag_suggestion_applied",
            detailJSON: "{}",
            occurredAt: 1_700_000_400
        )
    }
}

extension SearchResultPageSnapshot {
    static func s208SearchPage(filters: SearchFilterStateSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: "",
            totalCount: filters.tags.isEmpty ? 0 : 1,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension SearchFacetsSnapshot {
    static func s208Facets() -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: "",
            totalCount: 42,
            categories: [],
            fileKinds: [],
            tags: [
                SearchFacetCountSnapshot(
                    value: "finance",
                    label: "Finance",
                    count: 24,
                    selected: true,
                    disabled: false
                ),
                SearchFacetCountSnapshot(value: "tax", label: "Tax", count: 8, selected: true, disabled: false),
                SearchFacetCountSnapshot(value: "archive", label: "Archive", count: 0, selected: false, disabled: true)
            ],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: 1
        )
    }
}

actor S223UndoActionStore: CoreUndoActionLogging {
    private let actions: [UndoActionRecordSnapshot]
    private var requests: [String] = []

    init(actions: [UndoActionRecordSnapshot]) {
        self.actions = actions
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        requests.append(repoPath)
        return actions
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw CoreError.Internal(message: "S2-23 does not execute undo in C2-19 apply")
    }

    func listRequests() -> [String] {
        requests
    }
}

actor DetailLogRecordingChangeLister: CoreChangeLogListing {
    private let entries: [ChangeLogEntrySnapshot]

    init(entries: [ChangeLogEntrySnapshot]) {
        self.entries = entries
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        entries
    }
}
