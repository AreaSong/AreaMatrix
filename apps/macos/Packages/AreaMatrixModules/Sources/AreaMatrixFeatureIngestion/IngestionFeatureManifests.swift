import AreaMatrixCoreContracts

public enum IngestionFeatureManifests {
    public static let all: [FeatureManifest] = [
        FeatureManifestCatalog.onboarding,
        FeatureManifestCatalog.import,
        FeatureManifestCatalog.repositoryLifecycle
    ]
}
