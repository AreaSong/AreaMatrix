/// Process-scoped Core runtime composed by the App root.
///
/// Feature tests and high-risk flows may still construct an isolated bridge
/// explicitly. Production service defaults share this instance so Core
/// observation, probe coordination, and actor state do not fan out across a
/// new bridge for every protocol lookup.
enum CoreBridgeRuntime {
    static let shared = CoreBridge(
        interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() },
        importObservability: CoreImportObservabilityRecorder.live(
            makeTraceContext: { request in
                await ObservabilityRuntimeAssembly.shared.makeCoreTraceContext(request)
            },
            logger: AppLogger.shared
        ),
        remoteProviderProbePerformer: RemoteProviderProbeService.shared
    )
}
