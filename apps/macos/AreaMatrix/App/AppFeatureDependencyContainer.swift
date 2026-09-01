import Foundation

/// Feature-scoped dependency values composed by the App target.
///
/// Each scope contains only the protocols used by that feature. The live
/// values are assembled once by the application; tests can construct a scope
/// with focused doubles through the memberwise initializers.
struct AppFeatureDependencyContainer {
    let shared: SharedFeatureDependencies
    let onboarding: OnboardingFeatureDependencies
    let aiFeature: AIFeatureDependencies
    let fileActions: FileActionsFeatureDependencies
    let `import`: ImportFeatureDependencies
    let mainList: MainListFeatureDependencies
    let search: SearchFeatureDependencies
    let settings: SettingsFeatureDependencies
    let syncConflicts: SyncConflictsFeatureDependencies
    let diagnostics: DiagnosticsFeatureDependencies

    static func live(coreServices: AppCoreServices) -> Self {
        Self(
            shared: makeShared(coreServices: coreServices),
            onboarding: makeOnboarding(coreServices: coreServices),
            aiFeature: makeAIFeature(coreServices: coreServices),
            fileActions: makeFileActions(coreServices: coreServices),
            import: makeImport(coreServices: coreServices),
            mainList: makeMainList(coreServices: coreServices),
            search: makeSearch(coreServices: coreServices),
            settings: makeSettings(coreServices: coreServices),
            syncConflicts: makeSyncConflicts(coreServices: coreServices),
            diagnostics: makeDiagnostics()
        )
    }

    private static func makeShared(coreServices: AppCoreServices) -> SharedFeatureDependencies {
        SharedFeatureDependencies(
            errorMapper: coreServices.errorMapper,
            diagnosticsCollector: coreServices.diagnosticsCollector,
            repositoryWriteCoordinator: coreServices.repositoryWriteCoordinator,
            actionLogger: AppLogger.shared
        )
    }

    private static func makeOnboarding(coreServices: AppCoreServices) -> OnboardingFeatureDependencies {
        OnboardingFeatureDependencies(
            metadataRepairer: coreServices.metadataRepairer,
            repositoryReindexer: coreServices.repositoryReindexer,
            startupRecoverer: coreServices.startupRecoverer,
            repositoryWriteCoordinator: coreServices.repositoryWriteCoordinator,
            diagnosticsCollector: coreServices.diagnosticsCollector,
            errorMapper: coreServices.errorMapper
        )
    }

    private static func makeAIFeature(coreServices: AppCoreServices) -> AIFeatureDependencies {
        AIFeatureDependencies(
            aiCallLogLister: coreServices.aiCallLogLister,
            aiCallLogClearer: coreServices.aiCallLogClearer,
            aiClassificationSuggester: coreServices.aiClassificationSuggester,
            aiClassificationFallbackReader: coreServices.aiClassificationFallbackReader,
            aiPrivacyRules: coreServices.aiPrivacyRules,
            aiPrivacyRulesManager: coreServices.aiPrivacyRulesManager,
            aiSettingsLoader: coreServices.aiSettingsLoader,
            aiSettingsUpdater: coreServices.aiSettingsUpdater,
            aiSummaryStore: coreServices.aiSummaryStore,
            aiTagSuggestionStore: coreServices.aiTagSuggestionStore,
            classifierRuleEditor: coreServices.classifierRuleEditor,
            localModelStatusReader: coreServices.localModelStatusReader,
            localModelStorageLocationProvider: LocalModelStatusPlatformServices.makeStorageLocationProvider(),
            localModelInstallHelpOpener: LocalModelStatusPlatformServices.makeInstallHelpOpener(
                externalURLOpener: AppPlatformServices.externalURLStringOpener
            ),
            localModelFolderOpener: LocalModelStatusPlatformServices.makeFolderOpener(
                localURLOpener: AppPlatformServices.localFileURLOpener
            ),
            localModelDiagnosticsCopier: LocalModelStatusPlatformServices.makeDiagnosticsCopier(
                writer: AppPlatformServices.pasteboardStringWriter
            ),
            remoteProviderConfigurer: coreServices.remoteProviderConfigurer,
            remoteProviderCredentialStore: RemoteProviderKeychainCredentialStore(),
            contentLocaleSnapshotter: coreServices.repositoryContentLocaleSnapshotter,
            searchFiltering: coreServices.searchFiltering,
            privacyRuleRegistryReader: CoreAIPrivacyRuleRegistryReader(
                classifierReader: coreServices.classifierRuleEditor,
                facetReader: coreServices.searchFiltering
            )
        )
    }

    private static func makeFileActions(coreServices: AppCoreServices) -> FileActionsFeatureDependencies {
        FileActionsFeatureDependencies(
            classifierImpactPreviewer: coreServices.classifierImpactPreviewer,
            classifierRuleSaver: coreServices.classifierRuleSaver,
            iCloudConflictReviewer: coreServices.iCloudConflictReviewer,
            repositoryPathValidator: coreServices.repositoryPathValidator
        )
    }

    private static func makeImport(coreServices: AppCoreServices) -> ImportFeatureDependencies {
        ImportFeatureDependencies(
            actionLogger: AppLogger.shared,
            fileResourceAccess: ImportPlatformServices.fileResourceAccess,
            categoryPredictor: coreServices.categoryPredictor,
            batchFileLoader: CoreBridgeBatchFileLoader(fileLister: coreServices.fileLister),
            fileImporter: coreServices.importProgressImporter,
            batchFileImporter: coreServices.batchFileImporter,
            conflictBatcher: coreServices.conflictBatcher,
            fileLister: coreServices.fileLister,
            undoActionStore: coreServices.undoActionStore,
            batchSessionStore: AppPlatformServices.importBatchSessionStore,
            folderScanner: ImportPlatformServices.folderScanner,
            sourcePreflightInspector: ImportPlatformServices.sourcePreflightInspector,
            placeholderDownloader: LocalICloudPlaceholderDownloader()
        )
    }

    private static func makeMainList(coreServices: AppCoreServices) -> MainListFeatureDependencies {
        MainListFeatureDependencies(
            fileResourceAccess: ImportPlatformServices.fileResourceAccess,
            fileLister: coreServices.fileLister,
            fileDetailer: coreServices.fileDetailer,
            aiPrivacyRules: coreServices.aiPrivacyRules,
            aiSettingsLoader: coreServices.aiSettingsLoader,
            aiTagSuggestionStore: coreServices.aiTagSuggestionStore,
            batchCategoryChanger: coreServices.batchCategoryChanger,
            batchDeleter: coreServices.batchDeleter,
            categoryPredictor: coreServices.categoryPredictor,
            changeLogLister: coreServices.changeLogLister,
            externalChangesSyncer: coreServices.externalChangesSyncer,
            fileCategoryMover: coreServices.fileCategoryMover,
            fileDeleter: coreServices.fileDeleter,
            fileRenamer: coreServices.fileRenamer,
            iCloudConflictResolver: coreServices.iCloudConflictResolver,
            missingFileRecoverer: coreServices.missingFileRecoverer,
            missingFilePicker: AppPlatformServices.missingFilePicker,
            redoActionStore: coreServices.redoActionStore,
            searchFiltering: coreServices.searchFiltering,
            searchQuerying: coreServices.searchQuerying,
            semanticFallbackReader: coreServices.semanticFallbackReader,
            semanticSearching: coreServices.semanticSearching,
            tagStore: coreServices.tagStore,
            undoActionStore: coreServices.undoActionStore,
            repositoryWriteCoordinator: coreServices.repositoryWriteCoordinator,
            errorMapper: coreServices.errorMapper,
            diagnosticsCollector: coreServices.diagnosticsCollector
        )
    }

    private static func makeSearch(coreServices: AppCoreServices) -> SearchFeatureDependencies {
        SearchFeatureDependencies(
            savedSearchStore: coreServices.savedSearchStore,
            searchQuerying: coreServices.searchQuerying
        )
    }

    private static func makeSettings(coreServices: AppCoreServices) -> SettingsFeatureDependencies {
        SettingsFeatureDependencies(
            aiCallLogClearer: coreServices.aiCallLogClearer,
            aiCallLogLister: coreServices.aiCallLogLister,
            bindingContractInspector: coreServices.bindingContractInspector,
            categoryPredictor: coreServices.categoryPredictor,
            classifierRuleEditor: coreServices.classifierRuleEditor,
            interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() },
            configurationLoader: coreServices.configurationLoader,
            configurationUpdater: coreServices.configurationUpdater,
            coreVersionLoader: coreServices.coreVersionLoader,
            coreVersionReader: coreServices.coreVersionReader,
            emptyRepositoryOpener: coreServices.emptyRepositoryOpener,
            localModelStatusReader: coreServices.localModelStatusReader,
            overviewRegenerator: coreServices.overviewRegenerator,
            overviewRegenerationCoordinator: coreServices.overviewRegenerationCoordinator,
            platformCapabilityLoader: coreServices.platformCapabilityLoader,
            scanSessionReader: coreServices.scanSessionReader,
            appVersionReader: AppPlatformServices.appVersionReader,
            classifierFileOpener: AppPlatformServices.fileOpener,
            classifierFileRevealer: AppPlatformServices.fileRevealer,
            classifierFinderOpener: AppPlatformServices.finderOpener,
            classifierAccessibilityAnnouncer: AppPlatformServices.accessibilityAnnouncer,
            existingRepositoryMetadataReader: AppPlatformServices.existingRepositoryMetadataReader,
            metadataPresenceChecker: FileSystemRepoMetadataPresenceChecker(),
            finderOpener: AppPlatformServices.finderOpener,
            pathCopier: AppPlatformServices.pathCopier,
            generatedOverviewRevealer: AppPlatformServices.fileRevealer,
            accessibilityAnnouncer: AppPlatformServices.accessibilityAnnouncer,
            rootOverviewInspector: AppPlatformServices.rootOverviewInspector,
            rootOverviewRevealer: AppPlatformServices.fileRevealer,
            ignoreRulesManager: GeneralSettingsPlatformServices.makeIgnoreRulesManager(
                localURLOpener: AppPlatformServices.localFileURLOpener
            ),
            iCloudStatusDetector: IntegrationsSettingsPlatformServices.makeStatusDetector(),
            iCloudHelpOpener: IntegrationsSettingsPlatformServices.makeHelpOpener(
                externalURLOpener: AppPlatformServices.externalURLStringOpener
            ),
            aboutExternalLinkOpener: AboutSettingsPlatformServices.makeExternalLinkOpener(
                externalURLOpener: AppPlatformServices.externalURLStringOpener
            ),
            aboutStringCopier: AboutSettingsPlatformServices.makeStringCopier(
                writer: AppPlatformServices.pasteboardStringWriter
            ),
            diagnosticSummaryCopier: AdvancedSettingsPlatformServices.makeDiagnosticSummaryCopier(
                writer: AppPlatformServices.pasteboardStringWriter
            )
        )
    }

    private static func makeSyncConflicts(coreServices: AppCoreServices) -> SyncConflictsFeatureDependencies {
        SyncConflictsFeatureDependencies(
            iCloudConflictLister: coreServices.iCloudConflictLister,
            iCloudConflictReviewer: coreServices.iCloudConflictReviewer,
            repositoryPathValidator: coreServices.repositoryPathValidator,
            repositoryFinderOpener: AppPlatformServices.finderOpener,
            fileRevealer: AppPlatformServices.fileRevealer,
            systemCapabilityChecker: AppPlatformServices.systemCapabilityChecker,
            syncConflictDetector: coreServices.syncConflictDetector,
            conflictResolver: coreServices.syncConflictResolver
        )
    }

    private static func makeDiagnostics() -> DiagnosticsFeatureDependencies {
        DiagnosticsFeatureDependencies(
            runtime: { ObservabilityRuntimeAssembly.shared },
            packagePreviewer: AdvancedSettingsPlatformServices.diagnosticsPackagePreviewer(
                interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() }
            ),
            packageHandler: DefaultDiagnosticsPackageHandler()
        )
    }
}
