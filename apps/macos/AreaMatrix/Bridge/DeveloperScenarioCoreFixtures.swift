import Foundation

#if DEBUG
actor DeveloperConfigurationStore: CoreConfigurationLoading, CoreConfigurationUpdating {
    private var config: AppRepoConfigSnapshot

    init(config: AppRepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> AppRepoConfigSnapshot {
        config
    }

    func updateConfig(
        repoPath _: String,
        from currentConfig: AppRepoConfigSnapshot,
        to updatedConfig: AppRepoConfigSnapshot
    ) async throws -> AppRepoConfigSnapshot {
        guard currentConfig.revision == config.revision else {
            throw CoreError.RevisionConflict(
                resource: "developer-scenario-config",
                expectedRevision: currentConfig.revision,
                currentRevision: config.revision
            )
        }
        config = updatedConfig
        config.revision += 1
        return config
    }
}

actor DeveloperCapabilityLoader: CorePlatformCapabilitiesLoading {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        let available = PlatformCapabilitySupportSnapshot(
            status: .available,
            uiEnabled: true,
            requiresPermission: false,
            reason: nil
        )
        return PlatformCapabilitiesSnapshot(
            platform: platform,
            appVersion: appVersion,
            watcher: available,
            trash: available,
            shareExtension: available,
            cloudPlaceholder: available,
            securityBookmark: available
        )
    }
}

actor DeveloperOverviewRegenerator: CoreOverviewRegenerating {
    func overviewLanguageStatus(
        repoPath _: String,
        contentLocale: String
    ) async throws -> CoreOverviewLanguageStatusSnapshot {
        CoreOverviewLanguageStatusSnapshot(
            state: .synchronized,
            contentLocale: contentLocale,
            targetCount: 7,
            knownTargetCount: 7,
            missingTargetCount: 0,
            obsoleteTargetCount: 0,
            knownLocales: [contentLocale],
            knownFormatVersions: [1],
            reasons: []
        )
    }

    func prepareOverviewRegeneration(
        repoPath _: String,
        contentLocale: String
    ) async throws -> CoreOverviewRegenerationPlanSnapshot {
        CoreOverviewRegenerationPlanSnapshot(
            operationID: "developer-scenario",
            planToken: "developer-scenario-token",
            repositoryRevision: 7,
            contentLocale: contentLocale,
            formatContractVersion: 1,
            targetSetHash: "developer-scenario-targets",
            targetCount: 7,
            createCount: 0,
            replaceCount: 7,
            deleteCount: 0,
            includesRootAreaMatrixFile: false,
            warnings: []
        )
    }

    func startOverviewRegeneration(
        repoPath _: String,
        plan: CoreOverviewRegenerationPlanSnapshot
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: plan.operationID, contentLocale: plan.contentLocale, status: .readyToCommit)
    }

    func commitOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, contentLocale: "en", status: .completed)
    }

    func overviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, contentLocale: "en", status: .readyToCommit)
    }

    func recoverOverviewRegenerationOnStartup(
        repoPath _: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot? {
        nil
    }

    func resumeOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, contentLocale: "en", status: .readyToCommit)
    }

    func cancelOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, contentLocale: "en", status: .canceled)
    }

    func rollbackOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, contentLocale: "en", status: .rolledBack)
    }

    private func session(
        operationID: String,
        contentLocale: String,
        status: CoreOverviewRegenerationStatusSnapshot
    ) -> CoreOverviewRegenerationSessionSnapshot {
        CoreOverviewRegenerationSessionSnapshot(
            operationID: operationID,
            contentLocale: contentLocale,
            repositoryRevision: 7,
            formatContractVersion: 1,
            runSequence: 1,
            status: status,
            targetCount: 7,
            stagedCount: 7,
            appliedCount: status == .completed ? 7 : 0,
            restoredCount: 0,
            cancellationAllowed: status != .completed,
            errorCode: nil,
            createdAt: 1,
            updatedAt: 1,
            finishedAt: status == .completed ? 1 : nil
        )
    }
}
#endif
