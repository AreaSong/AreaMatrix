import Foundation

extension ImportSingleFilePreviewModel {
    var reasonSummary: String {
        guard let prediction else { return L10n.string("import.preview.noExplanation") }
        return L10n.format(
            "import.preview.classification-reason",
            prediction.reason.displayLabel,
            Int64(prediction.confidencePercent)
        )
    }

    var sourceSizeDescription: String? {
        let sizeBytes = source?.sizeBytes ?? currentPreflightResult?.sourceSizeBytes
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var filenameValidationMessage: String? {
        filenameValidationDisplayText.map(L10n.resolve)
    }

    var filenameValidationDisplayText: AppDisplayText? {
        ImportSingleFileFilenameValidator.validationDisplayText(for: suggestedName)
    }

    var preflightMessage: String? {
        if isICloudDownloading {
            return L10n.string("正在下载 iCloud 文件...")
        }
        return preflightStatus.message
    }

    var currentPreflightResult: ImportSingleFilePreflightResult? {
        switch preflightStatus {
        case let .ready(result), let .blocked(result):
            result
        case .idle, .checking:
            nil
        }
    }

    var progressCurrentPath: String {
        resolvedImportRelativePath
    }

    var showsICloudActions: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .iCloudPlaceholder, .iCloudDownloadFailed:
            return true
        case .none, .invalidFilename, .name, .duplicate, .corePreviewUnavailable, .sourceUnavailable, .error:
            return false
        }
    }

    var showsRetryPreviewAction: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .sourceUnavailable, .error:
            return true
        case .none, .invalidFilename, .name, .duplicate, .iCloudPlaceholder, .iCloudDownloadFailed,
             .corePreviewUnavailable:
            return false
        }
    }

    var showsConflictSection: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .none, .name, .duplicate:
            return true
        case .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return false
        }
    }

    var activeConflictPage: ImportSingleFileConflictPage? {
        guard let result = currentPreflightResult else { return nil }
        return ImportSingleFileConflictPage(conflict: result.conflict)
    }

    var importFailureMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping) = importStatus else { return nil }
        return mapping
    }

    var importDisabledReason: String? {
        importDisabledDisplayText.map(L10n.resolve)
    }

    var importDisabledDisplayText: AppDisplayText? {
        if importStatus.isImporting {
            return importStatus.blockingDisplayText ?? L10n.display("import.progress.importing")
        }
        if importStatus.isImported {
            return L10n.display("文件已导入")
        }
        if importStatus.isSkippedDuplicate {
            return L10n.display("重复文件已跳过")
        }
        if !hasReadyPrediction {
            return status.displayText ?? L10n.display("import.preflight.incomplete")
        }
        if selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.display("请选择导入分类")
        }
        if let filenameValidationDisplayText {
            return filenameValidationDisplayText
        }
        if duplicateResolution == .replace, !isReplaceConfirmed, replaceOptionVisibility == .enabled {
            return nil
        }
        if let duplicateResolutionBlockingDisplayText {
            return duplicateResolutionBlockingDisplayText
        }
        if nameConflictResolution == .replace, !isReplaceConfirmed, replaceOptionVisibility == .enabled {
            return nil
        }
        if let nameConflictBlockingText {
            return nameConflictBlockingText
        }
        if isDuplicateConflictResolvedForImport {
            return nil
        }
        if isNameConflictResolvedForImport {
            return nil
        }
        if let preflightBlocker = preflightStatus.importBlockingDisplayText() {
            return preflightBlocker
        }
        return nil
    }

    private var hasReadyPrediction: Bool {
        guard case .ready = status else { return false }
        return true
    }
}

private extension ImportSingleFileImportStatus {
    var isSkippedDuplicate: Bool {
        if case .skippedDuplicate = self { return true }
        return false
    }

    var isImported: Bool {
        if case .imported = self { return true }
        return false
    }

    var blockingDisplayText: AppDisplayText? {
        guard case let .importing(mode) = self else { return nil }
        return mode.importingBlockingDisplayText
    }
}
