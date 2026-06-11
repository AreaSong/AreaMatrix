import SwiftUI

enum PlatformDifferencesContractState: Equatable {
    case idle
    case loading
    case loaded(PlatformDifferencesBindingContractReport)
    case failed(PlatformDifferencesContractFailure)
}

enum PlatformDifferencesCapabilityState: Equatable {
    case idle
    case loading
    case loaded(PlatformDifferencesCapabilities)
    case failed(PlatformDifferencesCapabilityFailure)
}

struct PlatformDifferencesContractFailure: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

struct PlatformDifferencesCapabilityFailure: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

struct PlatformDifferencesCapabilityDisplayRow: Equatable, Identifiable {
    var name: String
    var support: PlatformDifferencesCapabilitySupport
    var detail: String
    var alternative: String?

    var id: String { name }
}

@MainActor
final class PlatformDifferencesViewModel: ObservableObject {
    @Published private(set) var contractState: PlatformDifferencesContractState = .idle
    @Published private(set) var capabilityState: PlatformDifferencesCapabilityState = .idle
    @Published private(set) var isChecking = false
    @Published var selectedTargetPlatform: PlatformDifferencesBindingTarget

    let hostPlatform: PlatformDifferencesPlatformId
    let repositoryPath: String?
    let appVersion: String
    let bindingVersion: Int64
    private let inspector: any PlatformDifferencesBindingContractInspecting
    private let capabilityLoader: any PlatformDifferencesCapabilityLoading

    init(
        hostPlatform: PlatformDifferencesPlatformId = .ios,
        repositoryPath: String? = nil,
        appVersion: String = "1",
        selectedTargetPlatform: PlatformDifferencesBindingTarget = .swift,
        bindingVersion: Int64 = 1,
        inspector: any PlatformDifferencesBindingContractInspecting = LivePlatformDifferencesCoreBridge(),
        capabilityLoader: any PlatformDifferencesCapabilityLoading = LivePlatformDifferencesCapabilityBridge()
    ) {
        self.hostPlatform = hostPlatform
        self.repositoryPath = repositoryPath
        self.appVersion = appVersion
        self.selectedTargetPlatform = selectedTargetPlatform
        self.bindingVersion = bindingVersion
        self.inspector = inspector
        self.capabilityLoader = capabilityLoader
    }

    var title: String { "Platform capabilities" }

    var repositoryText: String {
        if let repositoryPath, !repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Repository: \(repositoryPath)"
        }

        return "Repository: Not connected"
    }

    var actionTitle: String {
        isChecking ? "Checking contract..." : "Check contract"
    }

    func load() async {
        await loadCapabilities()
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

    func loadCapabilities() async {
        capabilityState = .loading

        do {
            capabilityState = .loaded(try await capabilityLoader.getPlatformCapabilities(
                platform: hostPlatform,
                appVersion: appVersion
            ))
        } catch {
            capabilityState = .failed(Self.capabilityFailure(for: error))
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

    private static func capabilityFailure(for error: Error) -> PlatformDifferencesCapabilityFailure {
        if let capabilityError = error as? PlatformDifferencesCapabilityError {
            return PlatformDifferencesCapabilityFailure(
                message: "Capability snapshot unavailable",
                recovery: capabilityError.recoverySuggestion,
                detail: capabilityError.localizedDescription
            )
        }

        return PlatformDifferencesCapabilityFailure(
            message: "Capability snapshot unavailable",
            recovery: "Retry the platform capability check.",
            detail: error.localizedDescription
        )
    }
}

struct PlatformDifferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlatformDifferencesViewModel
    @State private var isRepositorySettingsPresented = false
    private let onOpenRepositorySettings: (() -> Void)?

    @MainActor
    init(
        repositoryPath: String? = nil,
        onOpenRepositorySettings: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: PlatformDifferencesViewModel(repositoryPath: repositoryPath))
        self.onOpenRepositorySettings = onOpenRepositorySettings
    }

    @MainActor
    init(model: PlatformDifferencesViewModel, onOpenRepositorySettings: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.onOpenRepositorySettings = onOpenRepositorySettings
    }

    var body: some View {
        List {
            Section {
                Text(model.title)
                    .font(.title2.weight(.semibold))
                Text("Platform: \(model.hostPlatform.rawValue)")
                Text(model.repositoryText)
                Text("Core version: \(coreVersionText)")
                Text("Read-only binding contract check. No repository files are opened or modified.")
                    .foregroundStyle(.secondary)
                Text("Capability matrix does not replace operation-time permission checks.")
                    .foregroundStyle(.secondary)
            }

            capabilitySection

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

            actionsSection
        }
        .mobileLibraryListStyle()
        .navigationTitle(model.title)
        .sheet(isPresented: $isRepositorySettingsPresented) {
            NavigationStack {
                RepositorySettingsView(
                    repoPath: model.repositoryPath,
                    onOpenPlatformCapabilities: { isRepositorySettingsPresented = false }
                )
            }
        }
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

    @ViewBuilder
    private var capabilitySection: some View {
        switch model.capabilityState {
        case .idle, .loading:
            Section("Capability matrix") {
                HStack {
                    ProgressView()
                    Text("Checking platform capabilities...")
                }
            }
        case let .loaded(capabilities):
            PlatformDifferencesCapabilityMatrixSection(capabilities: capabilities)
        case let .failed(error):
            PlatformDifferencesCapabilityMatrixSection(capabilities: .unknownSnapshot(
                platform: model.hostPlatform,
                appVersion: model.appVersion,
                reason: error.detail
            ))
            Section("Capability status") {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.recovery)
                Text(error.detail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var coreVersionText: String {
        switch model.contractState {
        case let .loaded(report):
            return report.coreVersion
        default:
            return "Unknown"
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

    private var actionsSection: some View {
        Section("Actions") {
            Button("Open repository settings") {
                openRepositorySettings()
            }

            Button("Export diagnostics") {}
                .disabled(true)
            Text("Diagnostics are not available on this platform yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Close") {
                dismiss()
            }
        }
    }

    private func openRepositorySettings() {
        if let onOpenRepositorySettings {
            onOpenRepositorySettings()
            return
        }

        isRepositorySettingsPresented = true
    }
}
