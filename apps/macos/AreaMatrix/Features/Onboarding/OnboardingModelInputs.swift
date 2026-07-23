import Foundation

extension OnboardingModel {
    @MainActor
    func validateSelectedRepositoryPath() async {
        prepareRepositoryPathValidation()
        defer { finishRepositoryPathValidation() }

        let normalizedRepoPath = Self.normalizedRepositoryPath(repositoryPathText)
        let validation: RepoPathValidationSnapshot
        do {
            validation = try await pathValidator.validateRepoPath(repoPath: normalizedRepoPath)
        } catch {
            repositoryPathValidation = nil
            await routeValidationFailure(error, repoPath: normalizedRepoPath)
            return
        }

        repositoryPathValidation = validation
        repositoryPathErrorMapping = nil

        do {
            try await loadValidationContext(for: validation)
        } catch {
            await routeValidationFailure(error, repoPath: validation.repoPath)
            return
        }

        guard routeToRepairIfNeeded(validation) == false else { return }
        repositoryPathError = validatePathBlockingMessage(for: validation)
        repositoryPathErrorMapping = nil
        if repositoryPathError == nil {
            acceptContinueRequestedValidation(validation)
        }
    }

    @MainActor
    private func loadValidationContext(for validation: RepoPathValidationSnapshot) async throws {
        if shouldLoadLatestScanSession(for: validation) {
            latestScanSession = try await scanSessionReader.latestScanSession(repoPath: validation.repoPath)
            return
        }
        if validation.isInitialized {
            let metadata = try await existingRepositoryMetadataReader.metadata(repoPath: validation.repoPath)
            acceptExistingRepositoryMetadata(metadata)
        }
    }

    @MainActor
    private func routeToRepairIfNeeded(_ validation: RepoPathValidationSnapshot) -> Bool {
        guard validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) else {
            return false
        }
        route = .dbRepairConfirm(DatabaseRepairRouteState(
            repoPath: validation.repoPath,
            scanSession: latestScanSession,
            mapping: nil,
            returnRoute: .validatePath
        ))
        return true
    }

    @MainActor
    func routeValidationFailure(_ error: Error, repoPath: String) async {
        guard let mapping = await errorMapper.mapKnownErrorIfPresent(error) else {
            repositoryPathErrorMapping = nil
            repositoryPathError = L10n.message("路径字符串无法解析")
            return
        }

        repositoryPathErrorMapping = mapping
        repositoryPathError = mapping.userMessageDescriptor

        switch mapping.kind {
        case .db:
            route = .dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: repoPath,
                scanSession: latestScanSession,
                mapping: mapping,
                returnRoute: .validatePath
            ))
        case .config, .internal, .repoNotInitialized:
            routeMainRepositoryError(repoPath: repoPath, mapping: mapping)
        default:
            route = .validatePath
        }
    }

    func validatePathBlockingMessage(for validation: RepoPathValidationSnapshot) -> LocalizedMessage? {
        let checks: [(Bool, LocalizedMessage)] = [
            (
                validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix),
                L10n.message("请选择资料库根目录，而不是 .areamatrix 内部目录")
            ),
            (
                !validation.exists || validation.issues.contains(.missingPath),
                L10n.message("路径不存在，请选择已存在的文件夹")
            ),
            (
                !validation.isDirectory || validation.issues.contains(.notDirectory),
                L10n.message("onboarding.validate.chooseFolderPath")
            ),
            (
                !validation.isReadable || validation.issues.contains(.notReadable),
                L10n.message("AreaMatrix 没有读取该位置的权限")
            ),
            (
                !validation.isWritable || validation.issues.contains(.notWritable),
                L10n.message("AreaMatrix 没有写入该位置的权限")
            ),
            (validation.hasInsufficientAvailableCapacity, L10n.message("可用空间不足，请释放空间或选择其他路径")),
            (validation.hasMissingEnvironmentChecks, L10n.message("路径环境检查缺失，请重试或选择其他路径")),
            (
                validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession),
                L10n.message("该资料库存在未完成的扫描记录，请先进入修复流程")
            ),
            (
                validation.recommendedMode == nil && !validation.isInitialized,
                L10n.message("该路径暂时不能作为资料库使用")
            )
        ]

        return checks.first { $0.0 }?.1
    }

    func localRepositoryPathError(for value: String) -> LocalizedMessage? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return L10n.message("请输入资料库路径") }
        if trimmed.contains("\0") { return L10n.message("路径字符串无法解析") }
        if Self.pathContainsAreaMatrixComponent(trimmed) {
            return L10n.message("请选择资料库根目录，而不是 .areamatrix 内部目录")
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
}
