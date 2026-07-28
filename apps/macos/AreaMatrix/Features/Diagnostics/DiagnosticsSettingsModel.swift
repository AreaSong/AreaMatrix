import Foundation
import SwiftUI

struct DiagnosticsPackagePreviewSummary: Equatable {
    let packageID: String
    let eventCount: Int
    let estimatedSizeBytes: Int64
    let redactedFieldCount: Int
    let rejectedEventCount: Int
    let includesSensitiveEvents: Bool
    let includesFileNames: Bool
    let includesFullPaths: Bool
    let includesMetadataSnapshot: Bool
    let includedFiles: [String]

    init(_ preview: DiagnosticPackagePreview) {
        packageID = preview.manifest.packageID
        eventCount = preview.manifest.eventCount
        estimatedSizeBytes = preview.estimatedSizeBytes
        redactedFieldCount = preview.privacyReport.redactedFieldCount
        rejectedEventCount = preview.privacyReport.rejectedEventCount
        includesSensitiveEvents = preview.privacyReport.includesSensitiveEvents
        includesFileNames = preview.privacyReport.includesFileNames
        includesFullPaths = preview.privacyReport.includesFullPaths
        includesMetadataSnapshot = preview.privacyReport.includesMetadataSnapshot
        includedFiles = preview.privacyReport.includedFiles
    }
}

@MainActor
final class DiagnosticsSettingsModel: ObservableObject {
    @Published var configuration = AppObservabilityConfiguration.standard
    @Published var packageScope = DiagnosticsPackageScope.recentActivity
    @Published var includeSensitiveEventsInPackage = false
    @Published var includeFileNamesInPackage = false
    @Published var includeFullPathsInPackage = false
    @Published var includeMetadataSnapshotInPackage = false
    @Published var leasePolicy = AppObservabilityExpiryPolicy.timed
    @Published var leaseDurationHours = 24
    @Published var selectedIncidentID = ""
    @Published var incidentNote = ""
    @Published var isConsolePresented = false
    @Published private(set) var health = AppObservabilityHealth()
    @Published private(set) var events: [ObservabilityEventSnapshot] = []
    @Published private(set) var incidents: [ObservabilityIncidentSnapshot] = []
    @Published private(set) var catalog: ObservabilityCatalog?
    @Published private(set) var packagePreviewSummary: DiagnosticsPackagePreviewSummary?
    @Published private(set) var isPackagePreviewPresented = false
    @Published private(set) var offlineInspection: DiagnosticPackageInspection?
    @Published private(set) var feedback: DiagnosticsPageFeedback?
    @Published private(set) var isBusy = false

    private let runtime: ObservabilityRuntimeAssembly
    private let incidentManager: any DiagnosticsIncidentManaging
    private let packagePreviewer: any DiagnosticsPackagePreviewing
    private let packageHandler: any DiagnosticsPackageHandling
    private let repositoryURL: URL?
    private let nowMilliseconds: @Sendable () -> Int64
    private let sessionID: String
    private var preparedPreview: DiagnosticPackagePreview?

    init(
        runtime: ObservabilityRuntimeAssembly? = nil,
        incidentManager: (any DiagnosticsIncidentManaging)? = nil,
        packagePreviewer: any DiagnosticsPackagePreviewing =
            AdvancedSettingsPlatformServices.diagnosticsPackagePreviewer,
        packageHandler: (any DiagnosticsPackageHandling)? = nil,
        repositoryURL: URL? = nil,
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1000)
        },
        sessionID: String? = nil
    ) {
        let resolvedRuntime = runtime ?? .shared
        self.runtime = resolvedRuntime
        self.incidentManager = incidentManager ?? ObservabilityRuntimeIncidentAdapter(runtime: resolvedRuntime)
        self.packagePreviewer = packagePreviewer
        self.packageHandler = packageHandler ?? AdvancedSettingsPlatformServices.diagnosticsPackageHandler
        self.repositoryURL = repositoryURL
        self.nowMilliseconds = nowMilliseconds
        self.sessionID = sessionID ?? resolvedRuntime.sessionIDSnapshot()
    }

    var selectedIncident: ObservabilityIncidentSnapshot? {
        incidents.first { $0.id == selectedIncidentID }
    }

    func load() async {
        isBusy = true
        configuration = await runtime.configurationSnapshot()
        projectLeaseControls()
        await refreshRuntimeState()
        isBusy = false
    }

    func refreshRuntimeState() async {
        health = await runtime.health()
        events = await runtime.hub.recentEvents()
        catalog = await runtime.hub.catalogSnapshot()
        incidents = await incidentManager.incidentSnapshots().sorted {
            $0.markedAtMilliseconds > $1.markedAtMilliseconds
        }
        synchronizeIncidentSelection()
    }

    func applyConfiguration() async {
        isBusy = true
        do {
            let submitted = configurationForApply()
            try await runtime.update(submitted)
            configuration = submitted
            feedback = .success(L10n.message("observability.feedback.configurationApplied"))
            await refreshRuntimeState()
        } catch {
            feedback = .failure(L10n.message(
                "observability.error.configurationUpdate",
                technicalDetail: error.localizedDescription
            ))
        }
        isBusy = false
    }

    func setSensitiveLoggingEnabled(_ isEnabled: Bool) {
        configuration.includeSensitive = isEnabled
    }

    func selectMode(_ mode: AppObservabilityMode) {
        guard configuration.mode != mode else { return }
        configuration.mode = mode
        if mode == .diagnostic {
            configuration.retentionHours = 48
        }
    }

    func deleteLocalLogs() async {
        isBusy = true
        do {
            try await runtime.removeLocalLogs()
            preparedPreview = nil
            packagePreviewSummary = nil
            feedback = .success(L10n.message("observability.feedback.logsDeleted"))
            await refreshRuntimeState()
        } catch {
            feedback = .failure(L10n.message(
                "observability.error.logRemoval",
                technicalDetail: error.localizedDescription
            ))
        }
        isBusy = false
    }

    func markIncident() async {
        let note = incidentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let incidentID = await incidentManager.markIncident(note: note.isEmpty ? nil : note)
        incidentNote = ""
        selectedIncidentID = incidentID
        feedback = .success(L10n.message(
            "observability.feedback.incidentMarked",
            arguments: [.string(incidentID)]
        ))
        await refreshRuntimeState()
    }

    func updateIncidentStatus(_ status: ObservabilityIncidentStatus) async {
        guard !selectedIncidentID.isEmpty else { return }
        isBusy = true
        do {
            try await incidentManager.updateIncident(id: selectedIncidentID, status: status.rawValue)
            feedback = .success(L10n.message("observability.feedback.incidentUpdated"))
            await refreshRuntimeState()
        } catch {
            feedback = .failure(L10n.message(
                "observability.error.incidentUpdate",
                technicalDetail: error.localizedDescription
            ))
        }
        isBusy = false
    }

    func deleteSelectedIncident() async {
        guard !selectedIncidentID.isEmpty else { return }
        isBusy = true
        let deletedID = selectedIncidentID
        do {
            try await incidentManager.deleteIncident(id: deletedID)
            feedback = .success(L10n.message("observability.feedback.incidentDeleted"))
            await refreshRuntimeState()
        } catch {
            feedback = .failure(L10n.message(
                "observability.error.incidentDelete",
                technicalDetail: error.localizedDescription
            ))
        }
        isBusy = false
    }

    func preparePackagePreview() async {
        let sourceEvents = packageSourceEvents
        guard !sourceEvents.isEmpty else {
            feedback = .failure(L10n.message("observability.error.noPackageEvents"))
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let preview = try await packagePreviewer.makePreview(
                events: sourceEvents,
                privacySelection: packagePrivacySelection,
                repositoryURL: includeMetadataSnapshotInPackage ? repositoryURL : nil,
                summary: L10n.format("observability.package.generatedSummary", sourceEvents.count)
            )
            preparedPreview = preview
            packagePreviewSummary = DiagnosticsPackagePreviewSummary(preview)
            isPackagePreviewPresented = true
            feedback = nil
        } catch {
            feedback = .failure(Self.packageErrorMessage(error))
        }
    }

    func exportPreparedPackage() {
        guard let preparedPreview else { return }
        do {
            let suggestedName = "areamatrix-\(preparedPreview.manifest.packageID.prefix(8)).amdiagnostic"
            guard let url = try packageHandler.export(
                preparedPreview,
                suggestedFileName: suggestedName
            ) else { return }
            isPackagePreviewPresented = false
            feedback = .success(L10n.message(
                "observability.feedback.packageSaved",
                arguments: [.string(url.path)]
            ))
        } catch {
            feedback = .failure(Self.packageErrorMessage(error))
        }
    }

    func openPackage() {
        do {
            guard let inspection = try packageHandler.openPackage() else { return }
            offlineInspection = inspection
            feedback = nil
        } catch {
            feedback = .failure(Self.packageErrorMessage(error))
        }
    }

    func dismissPackagePreview() {
        isPackagePreviewPresented = false
    }

    func dismissOfflineInspection() {
        offlineInspection = nil
    }

    private var packageSourceEvents: [ObservabilityEventSnapshot] {
        switch packageScope {
        case .recentActivity: events
        case .selectedIncident: selectedIncident?.events ?? []
        }
    }

    private var packagePrivacySelection: DiagnosticPackagePrivacySelection {
        DiagnosticPackagePrivacySelection(
            includeSensitiveFields: includeSensitiveEventsInPackage,
            includeFileNames: includeFileNamesInPackage,
            includeFullPaths: includeFullPathsInPackage,
            includeMetadataSnapshot: includeMetadataSnapshotInPackage
        )
    }

    private func synchronizeIncidentSelection() {
        if !incidents.contains(where: { $0.id == selectedIncidentID }) {
            selectedIncidentID = incidents.first?.id ?? ""
        }
        if incidents.isEmpty {
            packageScope = .recentActivity
        }
    }

    private func configurationForApply() -> AppObservabilityConfiguration {
        guard configuration.mode.supportsExpiry else {
            var normalized = configuration
            normalized.modeLease = nil
            return normalized
        }
        return configuration.activating(
            policy: leasePolicy,
            durationHours: leaseDurationHours,
            nowMilliseconds: nowMilliseconds(),
            sessionID: sessionID
        )
    }

    private func projectLeaseControls() {
        guard configuration.mode.supportsExpiry, let lease = configuration.modeLease else { return }
        leasePolicy = lease.policy
        if lease.policy == .timed, let expiry = lease.expiresAtMilliseconds {
            let remaining = max(1, expiry - nowMilliseconds())
            leaseDurationHours = max(1, Int((remaining + 3_599_999) / 3_600_000))
        }
    }

    private static func packageErrorMessage(_ error: Error) -> LocalizedMessage {
        guard let packageError = error as? DiagnosticPackageError else {
            return L10n.message("observability.error.packageUnknown", technicalDetail: error.localizedDescription)
        }
        switch packageError {
        case .destinationExists: return L10n.message("observability.error.packageExists")
        case .durabilityUncertain: return L10n.message("observability.error.packageDurability")
        case .unsupportedSchema: return L10n.message("observability.error.packageSchema")
        case .checksumMismatch: return L10n.message("observability.error.packageChecksum")
        case .unsafeFile, .unexpectedEntry: return L10n.message("observability.error.packageUnsafe")
        case .limitExceeded: return L10n.message("observability.error.packageLimit")
        case .redactionFailed: return L10n.message("observability.error.packageRedaction")
        case .invalidDestination, .invalidPackage: return L10n.message("observability.error.packageInvalid")
        }
    }
}
