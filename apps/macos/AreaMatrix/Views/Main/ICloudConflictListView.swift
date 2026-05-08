import SwiftUI

enum ICloudConflictListCopy {
    static let title = "iCloud Conflicts"
    static let subtitle = "iCloud created conflict copies for these files. AreaMatrix will not delete any version automatically."
    static let loadingTitle = "Checking iCloud conflicts..."
    static let emptyTitle = "No iCloud conflicts found"
    static let errorTitle = "Unable to list iCloud conflicts"
    static let refreshAction = "Refresh"
    static let revealRepositoryAction = "Reveal repository in Finder"
    static let resolveAction = "Resolve..."
    static let revealAction = "Reveal"
    static let closeAction = "Close"
    static let diagnosticsAction = "Collect Diagnostics..."
}

enum ICloudConflictListAccessibilityID {
    static let page = "S1-36-C1-25-icloud-conflict-list"
    static let loading = "S1-36-C1-25-loading"
    static let emptyRefresh = "S1-36-C1-25-empty-refresh"
    static let error = "S1-36-C1-25-error"
    static let retry = "S1-36-C1-25-retry"
    static let collectDiagnostics = "S1-36-C1-25-collect-diagnostics"
    static let refresh = "S1-36-C1-25-refresh"
    static let revealRepository = "S1-36-C1-25-reveal-repository"
    static let close = "S1-36-close"

    static func resolve(conflictID: String) -> String {
        rowAction("resolve", conflictID: conflictID)
    }

    static func reveal(conflictID: String) -> String {
        rowAction("reveal", conflictID: conflictID)
    }

    private static func rowAction(_ action: String, conflictID: String) -> String {
        let safeID = conflictID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "-"
        }.joined()
        return "S1-36-C1-25-\(action)-\(safeID)"
    }
}

struct ICloudConflictListView: View {
    @StateObject private var model: ICloudConflictListModel
    @State private var resolvingConflict: ICloudConflictPairSnapshot?
    let onClose: () -> Void
    let onResolve: (ICloudConflictPairSnapshot) -> Void
    let onCollectDiagnostics: () -> Void

    init(
        model: ICloudConflictListModel,
        onClose: @escaping () -> Void,
        onResolve: @escaping (ICloudConflictPairSnapshot) -> Void,
        onCollectDiagnostics: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
        self.onResolve = onResolve
        self.onCollectDiagnostics = onCollectDiagnostics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 460)
        .task {
            if case .notLoaded = model.state {
                await model.load()
            }
        }
        .accessibilityIdentifier("S1-36-C1-25-icloud-conflict-list")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(ICloudConflictListCopy.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(ICloudConflictListCopy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking iCloud conflicts")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            loadingContent
        case .loaded(let conflicts) where conflicts.isEmpty:
            emptyContent
        case .loaded(let conflicts):
            conflictTable(conflicts)
        case .failed(let mapping):
            errorContent(mapping)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(ICloudConflictListCopy.loadingTitle)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(ICloudConflictListAccessibilityID.loading)
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(ICloudConflictListCopy.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text("AreaMatrix did not find conflicted copies in this repository.")
        } actions: {
            Button(ICloudConflictListCopy.refreshAction) {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.emptyRefresh)
        }
    }

    private func errorContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ContentUnavailableView {
            Label(ICloudConflictListCopy.errorTitle, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 4) {
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                if !mapping.rawContext.isEmpty {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } actions: {
            Button("Retry") {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.retry)
            Button(ICloudConflictListCopy.diagnosticsAction, action: onCollectDiagnostics)
                .accessibilityIdentifier(ICloudConflictListAccessibilityID.collectDiagnostics)
        }
        .accessibilityIdentifier(ICloudConflictListAccessibilityID.error)
    }

    private func conflictTable(_ conflicts: [ICloudConflictPairSnapshot]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(conflicts.count) conflicts")
                    .font(.headline)
                Spacer()
                revealFeedback
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Table(conflicts) {
                TableColumn("File") { conflict in
                    Text(conflict.fileDisplayName)
                        .lineLimit(1)
                }
                TableColumn("Original version") { conflict in
                    Text(conflict.originalVersionDisplay)
                        .lineLimit(1)
                        .foregroundStyle(conflict.originalPath == nil ? .secondary : .primary)
                }
                TableColumn("Conflict copy") { conflict in
                    Text(conflict.conflictedCopyDisplay)
                        .lineLimit(1)
                }
                TableColumn("Modified") { conflict in
                    Text(conflict.modifiedDisplay)
                        .monospacedDigit()
                }
                TableColumn("Status") { conflict in
                    Text(conflict.statusDisplay)
                }
                TableColumn("Action") { conflict in
                    rowActions(conflict)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func rowActions(_ conflict: ICloudConflictPairSnapshot) -> some View {
        HStack(spacing: 8) {
            Button(ICloudConflictListCopy.resolveAction) {
                resolvingConflict = conflict
                onResolve(conflict)
            }
            .disabled(model.isLoading || resolvingConflict?.id == conflict.id)
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.resolve(conflictID: conflict.id))

            Button(ICloudConflictListCopy.revealAction) {
                model.revealConflict(conflict)
            }
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.reveal(conflictID: conflict.id))
        }
    }

    @ViewBuilder
    private var revealFeedback: some View {
        switch model.revealState {
        case .idle:
            EmptyView()
        case .revealed(let message):
            Label(message, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Label(ICloudConflictListCopy.refreshAction, systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.refresh)

            Button {
                model.revealRepositoryInFinder()
            } label: {
                Label(ICloudConflictListCopy.revealRepositoryAction, systemImage: "folder")
            }
            .accessibilityIdentifier(ICloudConflictListAccessibilityID.revealRepository)

            Spacer()
            Button(ICloudConflictListCopy.closeAction, action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(ICloudConflictListAccessibilityID.close)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
