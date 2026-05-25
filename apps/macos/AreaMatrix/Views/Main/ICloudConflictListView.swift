import SwiftUI

enum ICloudConflictListCopy {
    static let title = "iCloud Conflicts"
    static let s220Title = "解决 iCloud 冲突"
    static let subtitle = """
    iCloud created conflict copies for these files. AreaMatrix will not delete any version automatically.
    """
    static let s220Subtitle = """
    Select a conflict found by Core before comparing versions. Listing is read-only and will not move files.
    """
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
    static let s220Page = "S2-20-C1-25-icloud-conflict-list"
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

enum ICloudConflictListPageContext: Equatable {
    case s136List
    case s220ConflictVisual

    var accessibilityID: String {
        switch self {
        case .s136List:
            ICloudConflictListAccessibilityID.page
        case .s220ConflictVisual:
            ICloudConflictListAccessibilityID.s220Page
        }
    }

    var title: String {
        switch self {
        case .s136List:
            ICloudConflictListCopy.title
        case .s220ConflictVisual:
            ICloudConflictListCopy.s220Title
        }
    }

    var subtitle: String {
        switch self {
        case .s136List:
            ICloudConflictListCopy.subtitle
        case .s220ConflictVisual:
            ICloudConflictListCopy.s220Subtitle
        }
    }

    var loadingTitle: String {
        switch self {
        case .s136List:
            ICloudConflictListCopy.loadingTitle
        case .s220ConflictVisual:
            "Loading conflict details..."
        }
    }

    func countLabel(conflictCount: Int) -> String {
        switch self {
        case .s136List:
            return "\(conflictCount) conflicts"
        case .s220ConflictVisual:
            return "\(conflictCount) conflict groups found"
        }
    }
}

struct ICloudConflictListView: View {
    @StateObject private var model: ICloudConflictListModel
    let pageContext: ICloudConflictListPageContext
    let onClose: () -> Void
    let onResolve: (ICloudConflictPairSnapshot) -> Void
    let onCollectDiagnostics: () -> Void

    init(
        model: ICloudConflictListModel,
        pageContext: ICloudConflictListPageContext = .s136List,
        onClose: @escaping () -> Void,
        onResolve: @escaping (ICloudConflictPairSnapshot) -> Void,
        onCollectDiagnostics: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.pageContext = pageContext
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
        .sheet(item: resolvingRouteBinding) { route in
            ICloudConflictMinimalSheet(
                model: ICloudConflictMinimalModel(
                    repoPath: route.repoPath,
                    conflictID: route.conflict.conflictID,
                    originalVersion: route.originalVersion,
                    conflictedCopyVersion: route.conflictedCopyVersion
                ),
                resolutionCapability: route.resolutionCapability,
                isTrashAvailable: OnboardingModel.isSystemTrashAvailable(),
                onCancel: model.closeResolvingConflict,
                onApply: { _, report, _ in
                    guard report?.status == .resolved else { return }
                    Task { await model.refresh() }
                    model.closeResolvingConflict()
                },
                onCollectDiagnostics: onCollectDiagnostics
            )
        }
        .accessibilityIdentifier(pageContext.accessibilityID)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(pageContext.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(pageContext.subtitle)
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
        case let .loaded(conflicts) where conflicts.isEmpty:
            emptyContent
        case let .loaded(conflicts):
            conflictTable(conflicts)
        case let .failed(mapping):
            errorContent(mapping)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(pageContext.loadingTitle)
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
                Text(pageContext.countLabel(conflictCount: conflicts.count))
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
                model.beginResolvingConflict(conflict)
                onResolve(conflict)
            }
            .disabled(model.isLoading || model.isResolving(conflict))
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
        case let .revealed(message):
            Label(message, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
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

    private var resolvingRouteBinding: Binding<ICloudConflictMinimalRouteContext?> {
        Binding(
            get: { model.resolvingRoute },
            set: { route in
                if route == nil { model.closeResolvingConflict() }
            }
        )
    }
}
