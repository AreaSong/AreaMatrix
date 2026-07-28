@testable import AreaMatrix
import Foundation
import XCTest

final class DiagnosticsSettingsUIProjectionTests: XCTestCase {
    @MainActor
    func testLoadWaitsForExpiredLeaseResolutionDuringRuntimeStartup() async throws {
        let fixture = try DiagnosticsUIFixture()
        defer { fixture.cleanup() }
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 2000)
        let runtime = ObservabilityRuntimeAssembly(
            hub: fixture.hub,
            core: DiagnosticsCoreSpy(),
            sessionID: "runtime-settings-session",
            scheduler: scheduler.runtimeScheduler
        )
        let expired = AppObservabilityConfiguration(
            mode: .developer,
            minimumSeverity: .debug,
            diskBudgetBytes: 100_000,
            retentionHours: 24,
            includeSensitive: false,
            modeLease: AppObservabilityModeLease(
                policy: .timed,
                activatedAtMilliseconds: 0,
                activationSessionID: "previous-session",
                expiresAtMilliseconds: 1000
            )
        )
        await fixture.hub.configure(expired)
        let model = DiagnosticsSettingsModel(runtime: runtime)

        await model.load()

        XCTAssertEqual(model.configuration, .standard)
        _ = await runtime.stop()
    }

    @MainActor
    func testInjectedRuntimeSessionIdentityIsUsedForNewModeLease() async throws {
        let fixture = try DiagnosticsUIFixture()
        defer { fixture.cleanup() }
        let runtime = ObservabilityRuntimeAssembly(
            hub: fixture.hub,
            core: DiagnosticsCoreSpy(),
            sessionID: "runtime-settings-session"
        )
        let model = DiagnosticsSettingsModel(runtime: runtime, nowMilliseconds: { 1000 })
        await model.load()
        model.configuration = .runtimeMode(.developer)

        await model.applyConfiguration()

        XCTAssertEqual(model.configuration.modeLease?.activationSessionID, "runtime-settings-session")
        _ = await runtime.stop()
    }

    @MainActor
    func testApplyConfigurationUpdatesCoreAndHubTogether() async throws {
        let fixture = try DiagnosticsUIFixture()
        defer { fixture.cleanup() }
        let core = DiagnosticsCoreSpy()
        let scheduler = TestObservabilityRuntimeScheduler(wallMilliseconds: 1000)
        let runtime = ObservabilityRuntimeAssembly(
            hub: fixture.hub,
            core: core,
            scheduler: scheduler.runtimeScheduler
        )
        let model = DiagnosticsSettingsModel(
            runtime: runtime,
            packagePreviewer: DiagnosticsPackagePreviewerSpy(),
            packageHandler: DiagnosticsPackageHandlerSpy(),
            nowMilliseconds: { 1000 },
            sessionID: "settings-session"
        )
        await fixture.hub.configure(.testDisabled)
        await model.load()

        let selected = AppObservabilityConfiguration(
            mode: .developer,
            minimumSeverity: .debug,
            diskBudgetBytes: 512 * 1024 * 1024,
            retentionHours: 72,
            includeSensitive: true
        )
        let expected = selected.activating(
            policy: .timed,
            durationHours: 24,
            nowMilliseconds: 1000,
            sessionID: "settings-session"
        )
        model.configuration = selected
        await model.applyConfiguration()

        let updatedConfiguration = await core.lastUpdatedConfiguration()
        let persistedConfiguration = await fixture.hub.configurationSnapshot()
        XCTAssertEqual(updatedConfiguration, ObservabilityConfig(
            sessionId: ObservabilityProcessIdentity.sessionID,
            mode: .developer,
            minimumSeverity: .debug,
            queueCapacity: 4096,
            includeSensitive: true
        ))
        XCTAssertEqual(persistedConfiguration, expected)
        XCTAssertEqual(
            model.feedback,
            .success(L10n.message("observability.feedback.configurationApplied"))
        )
    }
}

extension DiagnosticsSettingsUIProjectionTests {
    func testActivityAndTraceProjectionUseStableCatalogIdentity() throws {
        let events = makeDiagnosticsTraceFixture()
        let root = events.root
        let child = events.child
        let grandchild = events.grandchild

        let rows = DiagnosticsTraceProjection.rows([grandchild, child, root])
        XCTAssertEqual(rows.map(\.event.eventID), ["root", "child", "grandchild"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])

        let catalog = try ObservabilityCatalog.loadBundled().get()
        XCTAssertEqual(catalog.group(forActionID: child.actionID), "repository.import")
        XCTAssertNil(catalog.group(forActionID: "unregistered.action"))
        let projected = DiagnosticsConsoleProjection(events: [child], catalog: catalog)
            .filtered(using: .init())
            .events
        XCTAssertEqual(projected.first?.actionGroup, "repository.import")
        XCTAssertEqual(
            DiagnosticsCatalogPresentation.title(for: projected.first?.actionGroup).key,
            "observability.catalog.import.title"
        )
        XCTAssertEqual(
            DiagnosticsCatalogPresentation.title(for: nil).key,
            "observability.activity.other"
        )
        XCTAssertEqual(
            DiagnosticsEventPresentation.outcome("failed").key,
            "observability.outcome.failed"
        )
    }

    @MainActor
    func testPackagePreviewExportAndOpenUpdatePresentationState() async throws {
        let fixture = try DiagnosticsUIFixture()
        defer { fixture.cleanup() }
        await seedDiagnosticsHub(fixture.hub, eventID: "package-event")
        let catalog = await fixture.hub.catalogSnapshot()
        let acceptedEventIDs = await fixture.hub.recentEvents().map(\.eventID)
        XCTAssertNotNil(catalog)
        XCTAssertEqual(acceptedEventIDs, ["package-event"])
        let handler = DiagnosticsPackageHandlerSpy()
        let previewer = DiagnosticsPackagePreviewerSpy()
        let runtime = ObservabilityRuntimeAssembly(hub: fixture.hub, core: DiagnosticsCoreSpy())
        let repositoryURL = try fixture.makeRepositoryMetadata()
        let model = DiagnosticsSettingsModel(
            runtime: runtime,
            packagePreviewer: previewer,
            packageHandler: handler,
            repositoryURL: repositoryURL
        )
        await model.load()

        model.includeSensitiveEventsInPackage = true
        model.includeFileNamesInPackage = true
        model.includeFullPathsInPackage = true
        model.includeMetadataSnapshotInPackage = true
        await model.preparePackagePreview()

        let summary = try XCTUnwrap(model.packagePreviewSummary)
        assertAllSensitivePackageSummary(summary)
        XCTAssertTrue(model.isPackagePreviewPresented)
        let previewCalls = await previewer.calls()
        let previewCall = try XCTUnwrap(previewCalls.last)
        XCTAssertEqual(previewCall.eventIDs, ["package-event"])
        XCTAssertEqual(previewCall.privacySelection, .allSensitive(includeMetadataSnapshot: true))
        XCTAssertEqual(previewCall.repositoryURL, repositoryURL)

        model.exportPreparedPackage()

        XCTAssertEqual(handler.exportedPackageID, summary.packageID)
        XCTAssertFalse(model.isPackagePreviewPresented)
        guard case let .success(savedMessage) = model.feedback else {
            return XCTFail("Expected package saved feedback")
        }
        XCTAssertEqual(savedMessage.key, "observability.feedback.packageSaved")
        XCTAssertEqual(savedMessage.arguments, [.string(handler.exportURL.path)])

        let preview = try XCTUnwrap(handler.lastPreview)
        handler.inspection = makeDiagnosticsOfflineInspection(preview)
        model.openPackage()

        XCTAssertEqual(model.offlineInspection?.summary, "Offline inspection")
        XCTAssertEqual(model.offlineInspection?.events.map(\.eventID), ["offline-event"])
    }

    @MainActor
    func testPackagePreviewKeepsFourAuthorizationsIndependent() async throws {
        let fixture = try DiagnosticsUIFixture()
        defer { fixture.cleanup() }
        await seedDiagnosticsHub(fixture.hub, eventID: "authorization-event")
        let catalog = await fixture.hub.catalogSnapshot()
        let acceptedEventIDs = await fixture.hub.recentEvents().map(\.eventID)
        XCTAssertNotNil(catalog)
        XCTAssertEqual(acceptedEventIDs, ["authorization-event"])
        let repositoryURL = try fixture.makeRepositoryMetadata()
        let previewer = DiagnosticsPackagePreviewerSpy()
        let model = DiagnosticsSettingsModel(
            runtime: ObservabilityRuntimeAssembly(hub: fixture.hub, core: DiagnosticsCoreSpy()),
            packagePreviewer: previewer,
            packageHandler: DiagnosticsPackageHandlerSpy(),
            repositoryURL: repositoryURL
        )
        await model.load()

        let combinations = validDiagnosticsPrivacySelections()
        for selection in combinations {
            model.includeSensitiveEventsInPackage = selection.includeSensitiveFields
            model.includeFileNamesInPackage = selection.includeFileNames
            model.includeFullPathsInPackage = selection.includeFullPaths
            model.includeMetadataSnapshotInPackage = selection.includeMetadataSnapshot
            await model.preparePackagePreview()
            XCTAssertEqual(model.packagePreviewSummary?.includesSensitiveEvents, selection.includeSensitiveFields)
            XCTAssertEqual(model.packagePreviewSummary?.includesFileNames, selection.includeFileNames)
            XCTAssertEqual(model.packagePreviewSummary?.includesFullPaths, selection.includeFullPaths)
            XCTAssertEqual(model.packagePreviewSummary?.includesMetadataSnapshot, selection.includeMetadataSnapshot)
        }

        let calls = await previewer.calls()
        XCTAssertEqual(calls.map(\.privacySelection), combinations)
        XCTAssertEqual(
            calls.map(\.repositoryURL),
            combinations.map { $0.includeMetadataSnapshot ? repositoryURL : nil }
        )
    }

    func testCriticalDiagnosticsKeysResolveInBothInterfaceLanguages() {
        let runtime = AppLanguageRuntime(selection: .en)
        XCTAssertEqual(runtime.localizedString("settings.page.diagnostics"), "Diagnostics and Logs")
        XCTAssertEqual(runtime.localizedString("settings.advanced.openDiagnostics"), "Open Diagnostics")
        XCTAssertEqual(runtime.localizedString("observability.package.scope.incident"), "Selected incident")
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.sensitivePackage.title"),
            "Include sensitive event fields in this package?"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.metadataSnapshot.title"),
            "Include a repository metadata snapshot?"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.fileNames.title"),
            "Include real file names in this package?"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.fullPaths.title"),
            "Include complete file paths in this package?"
        )

        runtime.update(.zhHans)
        XCTAssertEqual(runtime.localizedString("settings.page.diagnostics"), "诊断与日志")
        XCTAssertEqual(runtime.localizedString("settings.advanced.openDiagnostics"), "打开诊断")
        XCTAssertEqual(runtime.localizedString("observability.package.scope.incident"), "所选问题记录")
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.sensitivePackage.title"),
            "在本次诊断包中包含敏感事件字段？"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.metadataSnapshot.title"),
            "包含资料库元数据快照？"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.fileNames.title"),
            "在本次诊断包中包含真实文件名？"
        )
        XCTAssertEqual(
            runtime.localizedString("observability.confirm.fullPaths.title"),
            "在本次诊断包中包含完整文件路径？"
        )
    }
}

private struct DiagnosticsTraceFixture {
    let root: ObservabilityEventSnapshot
    let child: ObservabilityEventSnapshot
    let grandchild: ObservabilityEventSnapshot
}

private func makeDiagnosticsTraceFixture() -> DiagnosticsTraceFixture {
    DiagnosticsTraceFixture(
        root: makeDiagnosticsUIEvent(
            id: "root",
            sequence: 2,
            parentSpanID: nil,
            semantic: DiagnosticsTestSemantic(
                actionID: "repository.import.confirmed",
                componentID: "core.repository.import",
                phase: "started"
            )
        ),
        child: makeDiagnosticsUIEvent(
            id: "child",
            sequence: 3,
            parentSpanID: "span-root",
            semantic: DiagnosticsTestSemantic(
                actionID: "repository.import.validation",
                componentID: "core.storage.import",
                phase: "completed"
            )
        ),
        grandchild: makeDiagnosticsUIEvent(
            id: "grandchild",
            sequence: 4,
            parentSpanID: "span-child",
            semantic: DiagnosticsTestSemantic(
                actionID: "repository.import.duplicate_resolution",
                componentID: "core.storage.dedup",
                phase: "skipped"
            )
        )
    )
}

private func seedDiagnosticsHub(_ hub: ObservabilityHub, eventID: String) async {
    await hub.configure(.testDisabled)
    await hub.ingestCoreEvent(makeDiagnosticsUIEvent(
        id: eventID,
        sequence: 1,
        parentSpanID: nil,
        semantic: DiagnosticsTestSemantic(
            actionID: "diagnostics.export.confirmed",
            componentID: "macos.ui",
            phase: "event"
        )
    ))
}

private func assertAllSensitivePackageSummary(_ summary: DiagnosticsPackagePreviewSummary) {
    XCTAssertEqual(summary.eventCount, 1)
    XCTAssertTrue(summary.includesSensitiveEvents)
    XCTAssertTrue(summary.includesFileNames)
    XCTAssertTrue(summary.includesFullPaths)
    XCTAssertTrue(summary.includesMetadataSnapshot)
    XCTAssertEqual(
        summary.includedFiles,
        DiagnosticPackageFormat.reportedEntryNames + [
            "attachments/\(DiagnosticPackageFormat.repositoryMetadataDirectoryName)/",
            DiagnosticPackageFormat.metadataRelativePath("index.db")
        ]
    )
}

private func validDiagnosticsPrivacySelections() -> [DiagnosticPackagePrivacySelection] {
    [false, true].flatMap { sensitive in
        [false, true].flatMap { fileNames in
            [false, true].flatMap { fullPaths in
                [false, true].map { metadata in
                    DiagnosticPackagePrivacySelection(
                        includeSensitiveFields: sensitive,
                        includeFileNames: fileNames,
                        includeFullPaths: fullPaths,
                        includeMetadataSnapshot: metadata
                    )
                }
            }
        }
    }.filter(\.isValid)
}
