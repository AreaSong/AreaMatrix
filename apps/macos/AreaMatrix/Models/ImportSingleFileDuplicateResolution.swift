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
        if duplicateResolution == .replace, !isReplaceConfirmed {
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
            return .ask
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
        guard let result = currentPreflightResult, case .duplicate = result.conflict else { return .hidden }
        guard importRequest?.allowReplaceDuringImport == true else { return .hidden }
        return importRequest?.isTrashAvailable == true ? .enabled : .disabled
    }

    func beginReplaceConfirmation() {
        guard duplicateResolution == .replace else { return }
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

    private func canSelectDuplicateResolution(_ strategy: ImportSingleFileDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility != .hidden
    }

    private func replaceConfirmationContext(incomingPath: String) -> ImportSingleFileReplaceConfirmationContext? {
        guard let result = currentPreflightResult else { return nil }
        guard case .duplicate(let existingPath) = result.conflict else { return nil }
        return ImportSingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: incomingPath,
            incomingSizeBytes: result.sourceSizeBytes,
            targetRelativePath: result.targetRelativePath,
            isTrashAvailable: replaceOptionVisibility == .enabled
        )
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
