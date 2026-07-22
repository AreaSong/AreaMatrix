@testable import AreaMatrix
import Foundation
import XCTest

func assertImportRowStatusTags(
    _ rows: [ImportBatchPreviewRow],
    _ expectedTags: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(rows.map(\.status.tag), expectedTags, file: file, line: line)
}

func assertImportRowStatusTags(
    _ rows: [ImportBatchCopyImportRow],
    _ expectedTags: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(rows.map(\.status.tag), expectedTags, file: file, line: line)
}

func assertImportRowStatusTags(
    _ rows: [ImportFolderPreviewRow],
    _ expectedTags: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(rows.map(\.status.tag), expectedTags, file: file, line: line)
}

func assertImportRowStatusDetails(
    _ rows: [ImportBatchPreviewRow],
    _ expectedDetailsByIndex: [Int: String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertImportRowStatusDetails(rows.map(\.status.detail), expectedDetailsByIndex, file: file, line: line)
}

func assertImportRowStatusDetails(
    _ rows: [ImportBatchCopyImportRow],
    _ expectedDetailsByIndex: [Int: String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertImportRowStatusDetails(rows.map(\.status.detail), expectedDetailsByIndex, file: file, line: line)
}

func assertImportRowStatusDetails(
    _ rows: [ImportFolderPreviewRow],
    _ expectedDetailsByIndex: [Int: String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertImportRowStatusDetails(rows.map(\.status.detail), expectedDetailsByIndex, file: file, line: line)
}

func assertImportStatusMessage(
    _ status: ImportBatchPreviewStatus,
    _ expectedMessage: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(status.message, expectedMessage, file: file, line: line)
}

func assertImportStatusMessage(
    _ status: ImportBatchCopyImportStatus,
    _ expectedMessage: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(status.message, expectedMessage, file: file, line: line)
}

func assertImportStatusMessage(
    _ status: ImportFolderPreviewStatus,
    _ expectedMessage: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(status.message, expectedMessage, file: file, line: line)
}

func assertImportBlockedByUnresolvedConflicts(
    _ importDisabledReason: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(importDisabledReason, "Resolve conflicts before importing blocked items", file: file, line: line)
}

func assertImportEnabled(
    _ importDisabledReason: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertNil(importDisabledReason, file: file, line: line)
}

private func assertImportRowStatusDetails(
    _ actualDetails: [String?],
    _ expectedDetailsByIndex: [Int: String],
    file: StaticString,
    line: UInt
) {
    for (index, expectedDetail) in expectedDetailsByIndex {
        guard actualDetails.indices.contains(index) else {
            XCTFail("Expected import row at index \(index)", file: file, line: line)
            continue
        }
        XCTAssertEqual(actualDetails[index], expectedDetail, file: file, line: line)
    }
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
func makeImportBatchMainListFixture(
    opening: RepositoryOpeningResult = .importSingleFileFixture(repoPath: importBatchRepoPath()),
    fileRevealer: (any RepositoryFileRevealing)? = nil
) -> ShellMainListFixture {
    makeShellMainListFixture(
        opening: opening,
        model: importBatchOnboardingModel(opening: opening, fileRevealer: fileRevealer)
    )
}

@MainActor
func importBatchOnboardingModel(
    opening: RepositoryOpeningResult? = nil,
    fileRevealer: (any RepositoryFileRevealing)? = nil
) -> OnboardingModel {
    let repositoryOpener = opening.map(ImportSingleFileStaticRepositoryOpener.init(opening:))
        ?? ShellRecordingRepositoryOpener(
            result: .success(.importSingleFileFixture(repoPath: importBatchRepoPath()))
        )

    return makeShellOnboardingModel(
        settingsReader: StaticSettingsReader(repoPath: nil),
        emptyRepositoryOpener: repositoryOpener,
        fileRevealer: fileRevealer ?? RecordingRepositoryFileRevealer(),
        accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
        helpOpener: NoopWelcomeHelpOpener()
    )
}
