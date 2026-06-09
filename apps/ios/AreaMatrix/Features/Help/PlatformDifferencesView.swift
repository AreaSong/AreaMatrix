import SwiftUI

enum PlatformDifferencesContractState: Equatable {
    case idle
    case loading
    case loaded(PlatformDifferencesBindingContractReport)
    case failed(PlatformDifferencesContractFailure)
}

struct PlatformDifferencesContractFailure: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

@MainActor
final class PlatformDifferencesViewModel: ObservableObject {
    @Published private(set) var contractState: PlatformDifferencesContractState = .idle
    @Published private(set) var isChecking = false
    @Published var selectedTargetPlatform: PlatformDifferencesBindingTarget

    let hostPlatform: String
    let bindingVersion: Int64
    private let inspector: any PlatformDifferencesBindingContractInspecting

    init(
        hostPlatform: String = "iOS",
        selectedTargetPlatform: PlatformDifferencesBindingTarget = .swift,
        bindingVersion: Int64 = 1,
        inspector: any PlatformDifferencesBindingContractInspecting = LivePlatformDifferencesCoreBridge()
    ) {
        self.hostPlatform = hostPlatform
        self.selectedTargetPlatform = selectedTargetPlatform
        self.bindingVersion = bindingVersion
        self.inspector = inspector
    }

    var title: String { "Platform capabilities" }

    var repositoryText: String { "Repository: Not connected" }

    var actionTitle: String {
        isChecking ? "Checking contract..." : "Check contract"
    }

    func load() async {
        await inspectContract()
    }

    func selectTargetPlatform(_ targetPlatform: PlatformDifferencesBindingTarget) {
        selectedTargetPlatform = targetPlatform
    }

    func inspectContract() async {
        isChecking = true
        contractState = .loading
        defer { isChecking = false }

        do {
            contractState = .loaded(try await inspector.inspectBindingContract(
                targetPlatform: selectedTargetPlatform,
                bindingVersion: bindingVersion
            ))
        } catch {
            contractState = .failed(Self.failure(for: error))
        }
    }

    private static func failure(for error: Error) -> PlatformDifferencesContractFailure {
        if let contractError = error as? PlatformDifferencesBindingContractError {
            return PlatformDifferencesContractFailure(
                message: "Binding contract unavailable",
                recovery: contractError.recoverySuggestion,
                detail: contractError.localizedDescription
            )
        }

        return PlatformDifferencesContractFailure(
            message: "Binding contract unavailable",
            recovery: "Retry the contract check.",
            detail: error.localizedDescription
        )
    }
}

struct PlatformDifferencesView: View {
    @StateObject private var model: PlatformDifferencesViewModel

    @MainActor
    init() {
        _model = StateObject(wrappedValue: PlatformDifferencesViewModel())
    }

    @MainActor
    init(model: PlatformDifferencesViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        List {
            Section {
                Text(model.title)
                    .font(.title2.weight(.semibold))
                Text("Platform: \(model.hostPlatform)")
                Text(model.repositoryText)
                Text("Read-only binding contract check. No repository files are opened or modified.")
                    .foregroundStyle(.secondary)
            }

            Section("Binding contract") {
                Picker("Binding target", selection: selectedTargetBinding) {
                    ForEach(PlatformDifferencesBindingTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                Button(model.actionTitle) {
                    Task { await model.inspectContract() }
                }
                .disabled(model.isChecking)
            }

            contractSection
        }
        .mobileLibraryListStyle()
        .navigationTitle(model.title)
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var contractSection: some View {
        switch model.contractState {
        case .idle, .loading:
            Section {
                HStack {
                    ProgressView()
                    Text("Checking binding contract...")
                }
            }
        case let .loaded(report):
            PlatformDifferencesReportSection(report: report)
        case let .failed(error):
            Section("Contract status") {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.recovery)
                Text(error.detail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedTargetBinding: Binding<PlatformDifferencesBindingTarget> {
        Binding(
            get: { model.selectedTargetPlatform },
            set: { target in
                model.selectTargetPlatform(target)
                Task { await model.inspectContract() }
            }
        )
    }
}

private struct PlatformDifferencesReportSection: View {
    let report: PlatformDifferencesBindingContractReport

    var body: some View {
        Section("Contract status") {
            LabeledContent("Target", value: report.targetPlatform.rawValue)
            LabeledContent("Contract version", value: "\(report.bindingVersion)")
            LabeledContent("Core version", value: report.coreVersion)
            ForEach(report.supportedApis) { api in
                PlatformDifferencesStatusRow(
                    title: api.name,
                    detail: api.capability,
                    status: api.status,
                    reason: api.reason
                )
            }
            ForEach(report.typeMappings) { mapping in
                PlatformDifferencesStatusRow(
                    title: "\(mapping.rustType) -> \(mapping.targetType)",
                    detail: mapping.udlType,
                    status: mapping.status,
                    reason: mapping.reason
                )
            }
            if report.missingCapabilities.isEmpty {
                Label("No missing binding capabilities for this target.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ForEach(report.missingCapabilities) { capability in
                    PlatformDifferencesStatusRow(
                        title: capability.label,
                        detail: capability.capability,
                        status: capability.status,
                        reason: capability.reason
                    )
                }
            }
        }
    }
}

private struct PlatformDifferencesStatusRow: View {
    let title: String
    let detail: String
    let status: PlatformDifferencesBindingSupportStatus
    let reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
