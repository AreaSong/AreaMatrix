import AreaMatrixCoreContracts

public enum LibraryFeatureManifests {
    public static let all: [FeatureManifest] = [
        FeatureManifestCatalog.mainList,
        FeatureManifestCatalog.detail,
        FeatureManifestCatalog.search,
        FeatureManifestCatalog.commandPalette
    ]
}
