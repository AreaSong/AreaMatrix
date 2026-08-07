import AreaMatrixCoreBridgeContract

extension CoreBridge: CoreBridgeRuntimeProviding {}

extension CoreBridge: CoreVersionLoading {}

extension CoreBridge:
    CoreConfigurationLoading,
    CoreConfigurationUpdating,
    CoreVersionReading,
    CoreDiagnosticsCollecting,
    CoreErrorMapping,
    CoreCategoryPredicting,
    CoreCommandIndexing,
    CoreRepositoryInitializing,
    CoreInitializedRepositoryPathValidating,
    CoreRepositoryPathValidating,
    CoreScanSessionReading {}
