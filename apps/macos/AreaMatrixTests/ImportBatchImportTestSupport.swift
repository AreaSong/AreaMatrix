@testable import AreaMatrix
import Foundation

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
    currentPath: String,
    skipped: Int = 0,
    pending: Int = 0,
    items: [ImportBatchProgressSnapshot.Item] = []
) -> ImportBatchProgressSnapshot {
    ImportBatchProgressSnapshot(
        completed: completed,
        failed: failed,
        total: total,
        remaining: remaining ?? max(total - completed - failed, 0),
        currentPath: currentPath,
        skipped: skipped,
        pending: pending,
        items: items
    )
}

func importBatchProgressItem(
    fileID: Int64? = nil,
    sourcePath: String,
    targetPath: String,
    phase: ImportBatchProgressSnapshot.Phase,
    errorMessage: String? = nil,
    existingRelativePath: String? = nil,
    importConflictBatch: ImportConflictBatchProgressMetadata? = nil
) -> ImportBatchProgressSnapshot.Item {
    ImportBatchProgressSnapshot.Item(
        fileID: fileID,
        sourcePath: sourcePath,
        targetPath: targetPath,
        phase: phase,
        errorMessage: errorMessage,
        existingRelativePath: existingRelativePath,
        importConflictBatch: importConflictBatch
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
