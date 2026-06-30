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
        guard let coreError = error as? CoreError else {
            repositoryPathErrorMapping = nil
            repositoryPathError = "路径字符串无法解析"
            return
        }

        let mapping = await errorMapper.mapCoreError(coreError)
        repositoryPathErrorMapping = mapping
        repositoryPathError = mapping.userMessage

        switch coreError {
        case .Db:
            route = .dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: repoPath,
                scanSession: latestScanSession,
                mapping: mapping,
                returnRoute: .validatePath
            ))
        case .Config, .Internal, .RepoNotInitialized:
            routeMainRepositoryError(repoPath: repoPath, mapping: mapping)
        default:
            route = .validatePath
        }
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
            )
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
}
