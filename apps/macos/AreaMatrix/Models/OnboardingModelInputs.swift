import Foundation

extension OnboardingModel {
    @MainActor
    func chooseImportSources(opening: RepositoryOpeningResult) {
        guard let urls = importPicker.chooseImportURLs() else { return }
        startImportEntry(opening: opening, source: .filePicker, urls: urls)
    }

    @MainActor
    func startImportEntry(
        opening: RepositoryOpeningResult,
        source: ImportEntrySource,
        urls: [URL],
        destination: ImportEntryDestination = .autoClassify
    ) {
        let fileURLs = Self.validFileURLs(from: urls)
        guard !fileURLs.isEmpty else {
            toastMessage = "Cannot import these items"
            accessibilityAnnouncer.announce("Cannot import these items")
            return
        }

        pendingImportEntry = ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: source,
            destination: destination,
            urls: fileURLs,
            kind: Self.importEntryKind(for: fileURLs)
        )
        toastMessage = nil
    }

    @MainActor
    func dismissImportEntry() {
        pendingImportEntry = nil
    }

    func validatePathBlockingMessage(for validation: RepoPathValidationSnapshot) -> String? {
        let checks: [(Bool, String)] = [
            (
                validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix),
                "请选择资料库根目录，而不是 .areamatrix 内部目录"
            ),
            (
                !validation.exists || validation.issues.contains(.missingPath),
                "路径不存在，请选择已存在的文件夹"
            ),
            (!validation.isDirectory || validation.issues.contains(.notDirectory), "请选择文件夹路径"),
            (
                !validation.isReadable || validation.issues.contains(.notReadable),
                "AreaMatrix 没有读取该位置的权限"
            ),
            (
                !validation.isWritable || validation.issues.contains(.notWritable),
                "AreaMatrix 没有写入该位置的权限"
            ),
            (validation.hasInsufficientAvailableCapacity, "可用空间不足，请释放空间或选择其他路径"),
            (validation.hasMissingEnvironmentChecks, "路径环境检查缺失，请重试或选择其他路径"),
            (
                validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession),
                "该资料库存在未完成的扫描记录，请先进入修复流程"
            ),
            (
                validation.recommendedMode == nil && !validation.isInitialized,
                "该路径暂时不能作为资料库使用"
            ),
        ]

        return checks.first { $0.0 }?.1
    }

    func localRepositoryPathError(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return "请输入资料库路径" }
        if trimmed.contains("\0") { return "路径字符串无法解析" }
        if Self.pathContainsAreaMatrixComponent(trimmed) {
            return "请选择资料库根目录，而不是 .areamatrix 内部目录"
        }
        return nil
    }

    static func normalizedRepositoryPath(_ value: String) -> String {
        (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    static func pathContainsAreaMatrixComponent(_ value: String) -> Bool {
        let normalized = normalizedRepositoryPath(value)
        return normalized.split(separator: "/", omittingEmptySubsequences: true).contains(".areamatrix")
    }

    static func validFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            url.isFileURL && !url.path.isEmpty
        }
    }

    private static func importEntryKind(for urls: [URL]) -> ImportEntryKind {
        if urls.contains(where: isDirectory) {
            return .folder
        }

        if urls.count == 1 {
            return .singleFile
        }

        return .multipleItems(urls.count)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
