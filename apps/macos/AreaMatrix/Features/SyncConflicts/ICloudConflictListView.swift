import SwiftUI

enum ICloudConflictListCopy {
    static var title: String {
        L10n.string("iCloud Conflicts")
    }

    static var iCloudConflictVisualTitle: String {
        L10n.string("icloud.conflict.title")
    }

    static var subtitle: String {
        L10n.string("icloud.conflict.list.subtitle")
    }

    static var iCloudConflictVisualSubtitle: String {
        L10n.string("icloud.conflict.list.selectionHint")
    }

    static var loadingTitle: String {
        L10n.string("Checking iCloud conflicts...")
    }

    static var emptyTitle: String {
        L10n.string("No iCloud conflicts found")
    }

    static var errorTitle: String {
        L10n.string("Unable to list iCloud conflicts")
    }

    static var refreshAction: String {
        L10n.string("Refresh")
    }

    static var revealRepositoryAction: String {
        L10n.string("Reveal repository in Finder")
    }

    static var resolveAction: String {
        L10n.string("Resolve...")
    }

    static var revealAction: String {
        L10n.string("Reveal")
    }

    static var closeAction: String {
        L10n.string("Close")
    }

    static var diagnosticsAction: String {
        L10n.string("Collect Diagnostics...")
    }
}

enum ICloudConflictListAccessibilityID {
    static let page = "icloud-conflicts-icloud-conflicts-core-icloud-conflict-list"
    static let iCloudConflictVisualPage = "icloud-conflict-review-icloud-conflicts-core-icloud-conflict-list"
    static let loading = "icloud-conflicts-icloud-conflicts-core-loading"
    static let emptyRefresh = "icloud-conflicts-icloud-conflicts-core-empty-refresh"
    static let error = "icloud-conflicts-icloud-conflicts-core-error"
    static let retry = "icloud-conflicts-icloud-conflicts-core-retry"
    static let collectDiagnostics = "icloud-conflicts-icloud-conflicts-core-collect-diagnostics"
    static let refresh = "icloud-conflicts-icloud-conflicts-core-refresh"
    static let revealRepository = "icloud-conflicts-icloud-conflicts-core-reveal-repository"
    static let close = "icloud-conflicts-close"

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
        return "icloud-conflicts-icloud-conflicts-core-\(action)-\(safeID)"
    }
}

enum ICloudConflictListPageContext: Equatable {
    case iCloudConflictListList
    case iCloudConflictVisualConflictVisual

    var accessibilityID: String {
        switch self {
        case .iCloudConflictListList:
            ICloudConflictListAccessibilityID.page
        case .iCloudConflictVisualConflictVisual:
            ICloudConflictListAccessibilityID.iCloudConflictVisualPage
        }
    }

    var title: String {
        switch self {
        case .iCloudConflictListList:
            ICloudConflictListCopy.title
        case .iCloudConflictVisualConflictVisual:
            ICloudConflictListCopy.iCloudConflictVisualTitle
        }
    }

    var subtitle: String {
        switch self {
        case .iCloudConflictListList:
            ICloudConflictListCopy.subtitle
        case .iCloudConflictVisualConflictVisual:
            ICloudConflictListCopy.iCloudConflictVisualSubtitle
        }
    }

    var loadingTitle: String {
        switch self {
        case .iCloudConflictListList:
            ICloudConflictListCopy.loadingTitle
        case .iCloudConflictVisualConflictVisual:
            L10n.string("Loading conflict details...")
        }
    }

    func countLabel(conflictCount: Int) -> String {
        switch self {
        case .iCloudConflictListList:
            L10n.plural("syncConflict.iCloud.count", count: conflictCount)
        case .iCloudConflictVisualConflictVisual:
            L10n.plural("syncConflict.iCloud.groupCount", count: conflictCount)
        }
    }
}

struct ICloudConflictListView: View {
    @StateObject private var model: ICloudConflictListModel
    let pageContext: ICloudConflictListPageContext
    let onClose: () -> Void
    let onResolve: (ICloudConflictPairSnapshot) -> Void
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let onCollectDiagnostics: () -> Void

    init(
        model: ICloudConflictListModel,
        pageContext: ICloudConflictListPageContext = .iCloudConflictListList,
        systemCapabilityChecker: any OnboardingSystemCapabilityChecking =
            AppPlatformServices.systemCapabilityChecker,
        onClose: @escaping () -> Void,
        onResolve: @escaping (ICloudConflictPairSnapshot) -> Void,
        onCollectDiagnostics: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.pageContext = pageContext
        self.onClose = onClose
        self.onResolve = onResolve
        self.systemCapabilityChecker = systemCapabilityChecker
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
                isTrashAvailable: systemCapabilityChecker.isTrashAvailable(),
                onCancel: model.closeResolvingConflict,
                onApply: { result in
                    guard result.report?.status == .resolved else { return }
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
                Text(L10n.format(
                    "syncConflict.error.severityRecoverability",
                    mapping.severity.rawValue,
                    mapping.recoverability.rawValue
                ))
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
