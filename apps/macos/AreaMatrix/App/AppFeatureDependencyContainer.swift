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

    static let live = AppFeatureDependencyContainer(
        shared: SharedFeatureDependencies(
            errorMapper: AppCoreServices.errorMapper,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            actionLogger: AppLogger.shared
        ),
        onboarding: OnboardingFeatureDependencies(
            metadataRepairer: AppCoreServices.metadataRepairer,
            repositoryReindexer: AppCoreServices.repositoryReindexer,
            startupRecoverer: AppCoreServices.startupRecoverer,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector,
            errorMapper: AppCoreServices.errorMapper
        ),
        aiFeature: AIFeatureDependencies(
            aiCallLogLister: AppCoreServices.aiCallLogLister,
            aiCallLogClearer: AppCoreServices.aiCallLogClearer,
            aiClassificationSuggester: AppCoreServices.aiClassificationSuggester,
            aiClassificationFallbackReader: AppCoreServices.aiClassificationFallbackReader,
            aiPrivacyRules: AppCoreServices.aiPrivacyRules,
            aiPrivacyRulesManager: AppCoreServices.aiPrivacyRulesManager,
            aiSettingsLoader: AppCoreServices.aiSettingsLoader,
            aiSettingsUpdater: AppCoreServices.aiSettingsUpdater,
            aiSummaryStore: AppCoreServices.aiSummaryStore,
            aiTagSuggestionStore: AppCoreServices.aiTagSuggestionStore,
            classifierRuleEditor: AppCoreServices.classifierRuleEditor,
            localModelStatusReader: AppCoreServices.localModelStatusReader,
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
            remoteProviderConfigurer: AppCoreServices.remoteProviderConfigurer,
            remoteProviderCredentialStore: RemoteProviderKeychainCredentialStore(),
            contentLocaleSnapshotter: AppCoreServices.repositoryContentLocaleSnapshotter,
            searchFiltering: AppCoreServices.searchFiltering,
            privacyRuleRegistryReader: CoreAIPrivacyRuleRegistryReader(
                classifierReader: AppCoreServices.classifierRuleEditor,
                facetReader: AppCoreServices.searchFiltering
            )
        ),
        fileActions: FileActionsFeatureDependencies(
            classifierImpactPreviewer: AppCoreServices.classifierImpactPreviewer,
            classifierRuleSaver: AppCoreServices.classifierRuleSaver,
            iCloudConflictReviewer: AppCoreServices.iCloudConflictReviewer,
            repositoryPathValidator: AppCoreServices.repositoryPathValidator
        ),
        import: ImportFeatureDependencies(
            actionLogger: AppLogger.shared,
            fileResourceAccess: ImportPlatformServices.fileResourceAccess,
            categoryPredictor: AppCoreServices.categoryPredictor,
            batchFileLoader: CoreBridgeBatchFileLoader(fileLister: AppCoreServices.fileLister),
            fileImporter: AppCoreServices.importProgressImporter,
            batchFileImporter: AppCoreServices.batchFileImporter,
            conflictBatcher: AppCoreServices.conflictBatcher,
            fileLister: AppCoreServices.fileLister,
            undoActionStore: AppCoreServices.undoActionStore,
            batchSessionStore: AppPlatformServices.importBatchSessionStore,
            folderScanner: ImportPlatformServices.folderScanner,
            sourcePreflightInspector: ImportPlatformServices.sourcePreflightInspector,
            placeholderDownloader: LocalICloudPlaceholderDownloader()
        ),
        mainList: MainListFeatureDependencies(
            fileResourceAccess: ImportPlatformServices.fileResourceAccess,
            fileLister: AppCoreServices.fileLister,
            fileDetailer: AppCoreServices.fileDetailer,
            aiPrivacyRules: AppCoreServices.aiPrivacyRules,
            aiSettingsLoader: AppCoreServices.aiSettingsLoader,
            aiTagSuggestionStore: AppCoreServices.aiTagSuggestionStore,
            batchCategoryChanger: AppCoreServices.batchCategoryChanger,
            batchDeleter: AppCoreServices.batchDeleter,
            categoryPredictor: AppCoreServices.categoryPredictor,
            changeLogLister: AppCoreServices.changeLogLister,
            commandIndexer: AppCoreServices.commandIndexer,
            externalChangesSyncer: AppCoreServices.externalChangesSyncer,
            fileCategoryMover: AppCoreServices.fileCategoryMover,
            fileDeleter: AppCoreServices.fileDeleter,
            fileRenamer: AppCoreServices.fileRenamer,
            iCloudConflictResolver: AppCoreServices.iCloudConflictResolver,
            missingFileRecoverer: AppCoreServices.missingFileRecoverer,
            missingFilePicker: AppPlatformServices.missingFilePicker,
            redoActionStore: AppCoreServices.redoActionStore,
            searchFiltering: AppCoreServices.searchFiltering,
            searchQuerying: AppCoreServices.searchQuerying,
            semanticFallbackReader: AppCoreServices.semanticFallbackReader,
            semanticSearching: AppCoreServices.semanticSearching,
            tagStore: AppCoreServices.tagStore,
            undoActionStore: AppCoreServices.undoActionStore,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            errorMapper: AppCoreServices.errorMapper,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector
        ),
        search: SearchFeatureDependencies(
            savedSearchStore: AppCoreServices.savedSearchStore,
            searchQuerying: AppCoreServices.searchQuerying
        ),
        settings: SettingsFeatureDependencies(
            aiCallLogClearer: AppCoreServices.aiCallLogClearer,
            aiCallLogLister: AppCoreServices.aiCallLogLister,
            bindingContractInspector: AppCoreServices.bindingContractInspector,
            categoryPredictor: AppCoreServices.categoryPredictor,
            classifierRuleEditor: AppCoreServices.classifierRuleEditor,
            interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() },
            configurationLoader: AppCoreServices.configurationLoader,
            configurationUpdater: AppCoreServices.configurationUpdater,
            coreVersionLoader: AppCoreServices.coreVersionLoader,
            coreVersionReader: AppCoreServices.coreVersionReader,
            emptyRepositoryOpener: AppCoreServices.emptyRepositoryOpener,
            localModelStatusReader: AppCoreServices.localModelStatusReader,
            overviewRegenerator: AppCoreServices.overviewRegenerator,
            overviewRegenerationCoordinator: AppCoreServices.overviewRegenerationCoordinator,
            platformCapabilityLoader: AppCoreServices.platformCapabilityLoader,
            scanSessionReader: AppCoreServices.scanSessionReader,
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
        ),
        syncConflicts: SyncConflictsFeatureDependencies(
            iCloudConflictLister: AppCoreServices.iCloudConflictLister,
            iCloudConflictReviewer: AppCoreServices.iCloudConflictReviewer,
            repositoryPathValidator: AppCoreServices.repositoryPathValidator,
            repositoryFinderOpener: AppPlatformServices.finderOpener,
            fileRevealer: AppPlatformServices.fileRevealer,
            systemCapabilityChecker: AppPlatformServices.systemCapabilityChecker,
            syncConflictDetector: AppCoreServices.syncConflictDetector,
            conflictResolver: AppCoreServices.syncConflictResolver
        ),
        diagnostics: DiagnosticsFeatureDependencies(
            runtime: { ObservabilityRuntimeAssembly.shared },
            packagePreviewer: AdvancedSettingsPlatformServices.diagnosticsPackagePreviewer(
                interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() }
            ),
            packageHandler: DefaultDiagnosticsPackageHandler()
        )
    )
}
