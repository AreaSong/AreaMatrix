@testable import AreaMatrix
import Foundation

/// Test-only dependency conveniences stay separate from shell fixtures so the
/// shell support file remains focused on route and model construction.
extension SharedFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.shared
    }
}

extension AIFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.aiFeature
    }
}

extension OnboardingFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.onboarding
    }
}

extension FileActionsFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.fileActions
    }
}

extension ImportFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.import
    }
}

extension MainListFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.mainList
    }
}

extension SearchFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.search
    }
}

extension SettingsFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.settings
    }
}

extension SyncConflictsFeatureDependencies {
    static var live: Self {
        AppDependencyContainer.live.feature.syncConflicts
    }
}

/// Test-target conveniences keep focused tests readable while production
/// feature initializers still require every platform capability explicitly.
extension ImportBatchPreviewModel {
    @MainActor
    convenience init(
        predictor: any CoreCategoryPredicting,
        duplicatePrechecker: (any ImportBatchDuplicatePrechecking)? = nil,
        nameConflictPrechecker: (any ImportBatchNameConflictPrechecking)? = nil
    ) {
        self.init(
            predictor: predictor,
            duplicatePrechecker: duplicatePrechecker,
            nameConflictPrechecker: nameConflictPrechecker,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension ImportDropPreviewModel {
    @MainActor
    convenience init(
        repoPath: String,
        predictor: any CoreCategoryPredicting
    ) {
        self.init(
            repoPath: repoPath,
            predictor: predictor,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension ImportFolderPreviewModel {
    @MainActor
    convenience init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        conflictPrechecker: any ImportFolderConflictPrechecking,
        scanner: any ImportFolderScanning,
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
    ) {
        self.init(
            predictor: predictor,
            importer: importer,
            errorMapper: errorMapper,
            conflictPrechecker: conflictPrechecker,
            scanner: scanner,
            placeholderDownloader: placeholderDownloader,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension ImportSingleFilePreviewModel {
    @MainActor
    convenience init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreFileImporting,
        preflight: any ImportSingleFilePreflighting,
        placeholderDownloader: any ICloudPlaceholderDownloading = ImportSingleFileStaticICloudDownloader(),
        errorMapper: any CoreErrorMapping
    ) {
        self.init(
            predictor: predictor,
            importer: importer,
            preflight: preflight,
            resourceAccess: ImportPlatformServices.fileResourceAccess,
            placeholderDownloader: placeholderDownloader,
            errorMapper: errorMapper
        )
    }
}

extension CoreImportBatchDuplicatePrechecker {
    init(fileLoader: any ImportBatchCoreFileLoading) {
        self.init(
            fileLoader: fileLoader,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension CoreImportFolderConflictPrechecker {
    init(fileLoader: any ImportBatchCoreFileLoading) {
        self.init(
            fileLoader: fileLoader,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension CoreImportSingleFilePreflight {
    init(fileLoader: any ImportBatchCoreFileLoading) {
        self.init(
            fileLoader: fileLoader,
            sourceInspector: ImportPlatformServices.sourcePreflightInspector,
            resourceAccess: ImportPlatformServices.fileResourceAccess
        )
    }
}

extension ImportSingleFileHasher {
    static func sha256Hex(for fileURL: URL) throws -> String {
        try sha256Hex(for: fileURL, resourceAccess: ImportPlatformServices.fileResourceAccess)
    }
}

extension ICloudConflictListModel {
    @MainActor
    convenience init(
        repoPath: String,
        conflictLister: any CoreICloudConflictListing,
        errorMapper: any CoreErrorMapping
    ) {
        self.init(
            repoPath: repoPath,
            conflictLister: conflictLister,
            errorMapper: errorMapper,
            repositoryFinderOpener: RecordingRepositoryFinderOpener(),
            fileRevealer: RecordingRepositoryFileRevealer()
        )
    }
}
