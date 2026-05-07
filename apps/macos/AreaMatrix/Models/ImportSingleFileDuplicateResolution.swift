import Foundation

enum ImportSingleFileDuplicateResolutionStrategy: String, CaseIterable, Identifiable, Equatable, Sendable {
    case skip
    case keepBoth
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skip:
            return "跳过导入（推荐）"
        case .keepBoth:
            return "保留两份（自动编号）"
        case .replace:
            return "替换已有文件（危险）"
        }
    }

    var detail: String {
        switch self {
        case .skip:
            return "不会创建新文件，保留资料库中的已有条目。"
        case .keepBoth:
            return "最终点击 Import 后由 Core 使用 KeepBoth 策略写入。"
        case .replace:
            return "必须先完成二次确认；最终点击 Import 后由 Core 安全替换。"
        }
    }

    var coreStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            return .skip
        case .keepBoth:
            return .keepBoth
        case .replace:
            return .overwrite
        }
    }
}

extension ImportSingleFilePreviewModel {
    var resolvedImportRelativePath: String {
        guard let result = currentPreflightResult else {
            return ImportSingleFilePreflightTarget.relativePath(
                category: selectedCategory,
                filename: suggestedName
            )
        }
        if case .name = result.conflict {
            return resolvedImportRelativePathForNameConflict
        }
        guard case .duplicate = result.conflict else {
            return result.targetRelativePath
        }

        switch duplicateResolution {
        case .skip:
            return result.targetRelativePath
        case .keepBoth:
            return result.keepBothTargetRelativePath ?? result.targetRelativePath
        case .replace:
            return result.targetRelativePath
        }
    }

    var primaryActionDisabledReason: String? {
        importDisabledReason
    }

    var shouldStartImportProgress: Bool {
        guard importDisabledReason == nil else { return false }
        return skippedDuplicateExistingPath == nil
    }

    var singleFilePrimaryActionTitle: String {
        if isPendingReplaceConfirmation {
            return "Continue"
        }
        return "Import"
    }

    var didSkipDuplicate: Bool {
        if case .skippedDuplicate = importStatus {
            return true
        }
        return false
    }

    var duplicateResolutionBlockingReason: String? {
        guard let result = currentPreflightResult else { return nil }
        guard case .duplicate = result.conflict else { return nil }

        switch duplicateResolution {
        case .skip:
            return nil
        case .keepBoth:
            return result.keepBothTargetRelativePath == nil ? "无法生成可用文件名" : nil
        case .replace:
            if replaceOptionVisibility == .disabled {
                return replaceOptionVisibility.blockingReason
            }
            return isReplaceConfirmed ? nil : "Replace 必须先进入二次确认"
        }
    }

    var isDuplicateConflictResolvedForImport: Bool {
        guard let result = currentPreflightResult else { return false }
        guard case .duplicate = result.conflict else { return false }
        return duplicateResolutionBlockingReason == nil
    }

    var skippedDuplicateExistingPath: String? {
        guard let result = currentPreflightResult else { return nil }
        guard case .duplicate(let existingPath) = result.conflict else { return nil }
        return duplicateResolution == .skip ? existingPath : nil
    }

    var resolvedDuplicateStrategy: DuplicateStrategy {
        guard let result = currentPreflightResult else { return .ask }

        switch result.conflict {
        case .duplicate:
            return duplicateResolution.coreStrategy
        case .name:
            switch nameConflictResolution {
            case .keepBoth, .renameIncoming:
                return .keepBoth
            case .replace:
                return .overwrite
            }
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return .ask
        }
    }

    func updateDuplicateResolution(_ strategy: ImportSingleFileDuplicateResolutionStrategy) {
        guard canSelectDuplicateResolution(strategy) else { return }
        duplicateResolution = strategy
        if strategy != .replace {
            markReplaceConfirmed(false)
            setPendingReplaceConfirmation(nil)
        }
    }

    var replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility {
        guard let result = currentPreflightResult else { return .hidden }
        guard case .duplicate = result.conflict else {
            guard case .name = result.conflict else { return .hidden }
            guard importRequest?.allowReplaceDuringImport == true else { return .hidden }
            return importRequest?.isTrashAvailable == true ? .enabled : .disabled
        }
        guard importRequest?.allowReplaceDuringImport == true else { return .hidden }
        return importRequest?.isTrashAvailable == true ? .enabled : .disabled
    }

    func beginReplaceConfirmation() {
        guard isPendingReplaceConfirmation else { return }
        guard let request = importRequest, let sourceURL = request.urls.first else { return }
        guard replaceOptionVisibility == .enabled else {
            blockImportForDuplicateResolution(replaceOptionVisibility.blockingReason)
            return
        }
        setPendingReplaceConfirmation(replaceConfirmationContext(incomingPath: sourceURL.path))
    }

    func cancelReplaceConfirmation() {
        setPendingReplaceConfirmation(nil)
    }

    func applyReplaceConfirmation(_ decision: ImportSingleFileReplaceConfirmationDecision) {
        guard pendingReplaceConfirmation == decision.context else {
            blockImportForDuplicateResolution("Replace confirmation context expired")
            markReplaceConfirmed(false)
            setPendingReplaceConfirmation(nil)
            return
        }
        guard decision.understandsReplace else {
            blockImportForDuplicateResolution("Replace 需要先勾选二次确认")
            markReplaceConfirmed(false)
            return
        }
        setPendingReplaceConfirmation(nil)
        markReplaceConfirmed(true)
    }

    func canSelectDuplicateResolution(_ strategy: ImportSingleFileDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility != .hidden
    }

    private func replaceConfirmationContext(incomingPath: String) -> ImportSingleFileReplaceConfirmationContext? {
        guard let result = currentPreflightResult else { return nil }
        let existingPath: String
        switch result.conflict {
        case .duplicate(let path), .name(let path):
            existingPath = path
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return nil
        }
        return ImportSingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: incomingPath,
            incomingSizeBytes: result.sourceSizeBytes,
            targetRelativePath: result.targetRelativePath,
            isTrashAvailable: replaceOptionVisibility == .enabled
        )
    }

    var isPendingReplaceConfirmation: Bool {
        guard !isReplaceConfirmed else { return false }
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .duplicate:
            return duplicateResolution == .replace
        case .name:
            return nameConflictResolution == .replace
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return false
        }
    }
}

enum ImportSingleFileDuplicateKeepBothPreview {
    static func nextAvailablePath(
        preferredPath: String,
        existingPaths: Set<String>,
        limit: Int = 1_000
    ) -> String? {
        guard existingPaths.contains(preferredPath) else { return preferredPath }

        let nsPath = preferredPath as NSString
        let directory = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent as NSString
        let base = filename.deletingPathExtension
        let ext = filename.pathExtension

        for suffix in 1...limit {
            let candidateName = numberedFilename(base: base, ext: ext, suffix: suffix)
            let candidate = directory.isEmpty ? candidateName : "\(directory)/\(candidateName)"
            if !existingPaths.contains(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func numberedFilename(base: String, ext: String, suffix: Int) -> String {
        if base.hasPrefix("."), ext.isEmpty {
            return "\(base)_\(suffix)"
        }
        return ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
    }
}

enum ImportSingleFileNameConflictResolution: Hashable, Sendable {
    case keepBoth
    case renameIncoming(String)
    case replace

    var title: String {
        switch self {
        case .keepBoth:
            return "保留两份（自动编号，推荐）"
        case .renameIncoming:
            return "重命名导入文件..."
        case .replace:
            return "替换已有文件（危险）"
        }
    }

    var detail: String {
        switch self {
        case .keepBoth:
            return "导入文件会使用自动编号，不覆盖已有文件。"
        case .renameIncoming(let name):
            return "导入文件将保存为 \(name)，已有文件保持不变。"
        case .replace:
            return "必须先完成二次确认；旧文件会移到系统废纸篓。"
        }
    }
}

extension ImportSingleFilePreviewModel {
    var resolvedImportFilename: String {
        guard let result = currentPreflightResult, case .name = result.conflict else {
            return suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch nameConflictResolution {
        case .keepBoth, .replace:
            return suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .renameIncoming:
            return resolvedNameConflictFilename
        }
    }

    var resolvedNameConflictFilename: String {
        switch nameConflictResolution {
        case .keepBoth:
            guard let path = currentPreflightResult?.keepBothTargetRelativePath else {
                return suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (path as NSString).lastPathComponent
        case .renameIncoming(let name):
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        case .replace:
            return suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var resolvedImportRelativePathForNameConflict: String {
        guard let result = currentPreflightResult else {
            return ImportSingleFilePreflightTarget.relativePath(
                category: selectedCategory,
                filename: resolvedNameConflictFilename
            )
        }
        switch nameConflictResolution {
        case .keepBoth:
            return result.keepBothTargetRelativePath ?? result.targetRelativePath
        case .renameIncoming:
            return ImportSingleFilePreflightTarget.relativePath(
                category: selectedCategory,
                filename: resolvedNameConflictFilename
            )
        case .replace:
            return result.targetRelativePath
        }
    }

    var nameConflictResolutionBlockingReason: String? {
        guard let result = currentPreflightResult, case .name = result.conflict else { return nil }
        switch nameConflictResolution {
        case .keepBoth:
            return result.keepBothTargetRelativePath == nil ? "无法生成可用文件名" : nil
        case .renameIncoming(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let validation = ImportSingleFileFilenameValidator.validationMessage(for: trimmed) {
                return validation
            }
            let targetPath = ImportSingleFilePreflightTarget.relativePath(
                category: selectedCategory,
                filename: trimmed
            )
            return result.existingPaths.contains(targetPath) ? "新文件名仍然冲突" : nil
        case .replace:
            if replaceOptionVisibility == .disabled {
                return replaceOptionVisibility.blockingReason
            }
            return isReplaceConfirmed ? nil : "Replace 必须先进入二次确认"
        }
    }

    var isNameConflictResolvedForImport: Bool {
        guard let result = currentPreflightResult else { return false }
        guard case .name = result.conflict else { return false }
        return nameConflictResolutionBlockingReason == nil
    }

    func updateNameConflictResolution(_ resolution: ImportSingleFileNameConflictResolution) {
        guard canSelectNameConflictResolution(resolution) else { return }
        setNameConflictResolution(resolution)
        if resolution != .replace {
            markReplaceConfirmed(false)
            setPendingReplaceConfirmation(nil)
        }
    }

    func renameIncomingNameConflictFile(to name: String) {
        updateNameConflictResolution(.renameIncoming(name))
    }

    func canSelectNameConflictResolution(_ resolution: ImportSingleFileNameConflictResolution) -> Bool {
        resolution != .replace || replaceOptionVisibility == .enabled
    }
}
