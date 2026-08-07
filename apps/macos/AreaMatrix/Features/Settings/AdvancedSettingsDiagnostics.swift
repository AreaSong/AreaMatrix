import AreaMatrixCoreBridgeContract
import Foundation
import SwiftUI

struct SettingsDiagnosticsGeneration {
    private var value = 0

    mutating func begin() -> Int {
        value += 1
        return value
    }

    mutating func invalidate() {
        value += 1
    }

    func isCurrent(_ generation: Int) -> Bool {
        value == generation
    }
}

protocol CoreVersionReading: Sendable {
    func coreVersion() async throws -> String
}

protocol AppVersionReading: Sendable {
    func appVersion() -> String
}

protocol AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws
}

struct AdvancedSettingsVersionInfo: Equatable {
    var appVersion: String
    var coreVersion: String
    var repoSchemaVersion: Int64?

    static let unknown = AdvancedSettingsVersionInfo(
        appVersion: "Unknown",
        coreVersion: "Unknown",
        repoSchemaVersion: nil
    )

    var repoSchemaVersionLabel: String {
        repoSchemaVersion.map { "v\($0)" } ?? L10n.string("Unknown")
    }
}

enum AdvancedSettingsDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(AdvancedSettingsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self { return true }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

enum AdvancedSettingsActionFeedback: Equatable {
    case success(LocalizedMessage)
    case failed(AdvancedSettingsError)
}

enum AdvancedSettingsDiagnosticSummaryError: Error, Equatable, LocalizedError {
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .copyRejected:
            L10n.string("settings.advanced.diagnosticsCopyRejected")
        }
    }
}

struct DiagnosticsTraceRow: Identifiable {
    var id: String {
        "\(event.eventID)-\(depth)"
    }

    let event: ObservabilityEventSnapshot
    let depth: Int
}

enum DiagnosticsTraceProjection {
    static func rows(_ events: [ObservabilityEventSnapshot]) -> [DiagnosticsTraceRow] {
        var parentBySpan: [String: String] = [:]
        for event in events {
            if let parentSpanID = event.parentSpanID {
                parentBySpan[event.spanID] = parentSpanID
            }
        }
        return events.sortedForDisplay.map { event in
            DiagnosticsTraceRow(event: event, depth: depth(for: event, parents: parentBySpan))
        }
    }

    private static func depth(
        for event: ObservabilityEventSnapshot,
        parents: [String: String]
    ) -> Int {
        var visited: Set<String> = [event.spanID]
        var parent = event.parentSpanID
        var depth = 0
        while let value = parent, depth < 8, visited.insert(value).inserted {
            depth += 1
            parent = parents[value]
        }
        return depth
    }
}

enum DiagnosticsEventPresentation {
    static func outcome(_ value: String) -> LocalizedMessage {
        switch value {
        case "started": L10n.message("observability.outcome.started")
        case "succeeded": L10n.message("observability.outcome.succeeded")
        case "failed": L10n.message("observability.outcome.failed")
        case "cancelled": L10n.message("observability.outcome.cancelled")
        case "skipped": L10n.message("observability.outcome.skipped")
        case "degraded": L10n.message("observability.outcome.degraded")
        default: L10n.message("observability.outcome.recorded")
        }
    }
}

struct DiagnosticsPackageOverview: View {
    let inspection: DiagnosticPackageInspection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.string("observability.package.manifest")).font(.headline)
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.id"),
                    value: inspection.manifest.packageID
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.schema"),
                    value: String(inspection.manifest.schemaVersion)
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.events"),
                    value: String(inspection.manifest.eventCount)
                )
                Divider()
                Text(L10n.string("observability.package.privacyReport")).font(.headline)
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.redacted"),
                    value: String(inspection.privacyReport.redactedFieldCount)
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.rejected"),
                    value: String(inspection.privacyReport.rejectedEventCount)
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.sensitiveEvents"),
                    value: inspection.privacyReport.includesSensitiveEvents
                        ? L10n.string("settings.value.yes")
                        : L10n.string("settings.value.no")
                )
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.package.metadataSnapshot"),
                    value: inspection.privacyReport.includesMetadataSnapshot
                        ? L10n.string("settings.value.yes")
                        : L10n.string("settings.value.no")
                )
                Divider()
                Text(L10n.string("observability.package.summary")).font(.headline)
                Text(inspection.summary).textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

extension [ObservabilityEventSnapshot] {
    var sortedForDisplay: [ObservabilityEventSnapshot] {
        sorted {
            if $0.sequenceNumber == $1.sequenceNumber {
                return $0.wallTimestampMilliseconds < $1.wallTimestampMilliseconds
            }
            return $0.sequenceNumber < $1.sequenceNumber
        }
    }
}

extension String {
    var diagnosticsShortTechnicalID: String {
        count > 18 ? "\(prefix(8))…\(suffix(6))" : self
    }
}
