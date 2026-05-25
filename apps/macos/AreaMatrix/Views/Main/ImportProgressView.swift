import SwiftUI

struct ImportProgressView: View {
    let state: ImportProgressRouteState
    let onStopAfterCurrentFile: () -> Void
    let onViewDetails: () -> Void
    let onRetryCurrentItem: () -> Void
    let onStopAndViewResults: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void
    let onOpenRepositoryInFinder: () -> Void

    @State private var isStopConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.toolbarText)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(state.titleText)
                    .font(.headline)
                Text(state.bannerText)
                Text("当前：\(state.currentPath)")
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.items) { item in
                    ImportingListRow(item: item)
                }
            }
            .accessibilityElement(children: .contain)

            if state.isFailed {
                fatalErrorPanel
            }

            HStack {
                Button(state.detailsButtonTitle) {
                    onViewDetails()
                }
                if state.isRunning {
                    Button(stopButtonTitle) {
                        isStopConfirmationPresented = true
                    }
                    .disabled(state.stopState != .idle)
                }
            }
        }
        .padding(24)
        .alert("停止剩余导入？", isPresented: $isStopConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive, action: onStopAfterCurrentFile)
        } message: {
            Text("已完成的文件会保留，未开始的文件会取消，当前文件会处理到安全点后停止。")
        }
        .alert("Collect Diagnostics?", isPresented: diagnosticsConfirmationBinding) {
            Button("Cancel", role: .cancel, action: onCancelDiagnostics)
            Button("Collect Diagnostics...", action: onConfirmDiagnostics)
        } message: {
            Text("Diagnostics do not include user file contents, are not uploaded, and paths/usernames are redacted.")
        }
    }

    private var fatalErrorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("导入已暂停", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("已完成 \(state.completed)，失败 \(state.failed)，未开始 \(state.remaining + state.pending)")
            Text("当前失败项：\(state.currentPath)")
                .textSelection(.enabled)
            if let errorMapping = state.errorMapping {
                Text("错误代码：\(errorMapping.kind.rawValue)")
                Text(errorMapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            Text("已完成的文件会保留。未开始的文件不会自动导入。")
            Text("AreaMatrix 会先确认 staging 状态，再允许重试当前项。")
                .foregroundStyle(.secondary)
            Text(state.retryStatusText)
                .font(.caption)
                .foregroundStyle(state.canRetryCurrentItem ? .green : .secondary)
            diagnosticsStatus
            HStack {
                Button("Retry current item", action: onRetryCurrentItem)
                    .disabled(!state.canRetryCurrentItem)
                Button("Stop and view results", action: onStopAndViewResults)
                    .keyboardShortcut(.defaultAction)
                Button("Collect Diagnostics...", action: onRequestDiagnostics)
                    .disabled(diagnosticsIsCollecting)
                if state.isRepositoryFinderAvailable {
                    Button("Open repository in Finder", action: onOpenRepositoryInFinder)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch state.diagnostics {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Collecting diagnostics...", systemImage: "doc.badge.gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            Label("Diagnostics collected: \(snapshot.snapshotPath)", systemImage: "doc.badge.gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(mapping):
            Label("Diagnostics failed: \(mapping.userMessage)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var stopButtonTitle: String {
        switch state.stopState {
        case .idle:
            "Stop after current file"
        case .stopping:
            "Stopping..."
        case .stopped:
            "Stopped"
        }
    }

    private var diagnosticsIsCollecting: Bool {
        if case .collecting = state.diagnostics { return true }
        return false
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmingPrivacy = state.diagnostics { return true }
                return false
            },
            set: { _ in }
        )
    }
}

private struct ImportingListRow: View {
    let item: ImportBatchProgressSnapshot.Item

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.targetPath)
                    .lineLimit(1)
                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if item.sourcePath != item.targetPath {
                    Text(item.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(item.phase.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(phaseColor)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.phase {
        case .copying, .hashing, .classifying:
            ProgressView()
                .controlSize(.small)
        case .moving:
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.orange)
        case .writingIndex:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private var phaseColor: Color {
        switch item.phase {
        case .failed:
            .red
        case .done:
            .green
        case .moving:
            .orange
        case .copying, .pending, .hashing, .classifying, .writingIndex:
            .secondary
        }
    }
}

struct CommandPaletteView: View {
    @Binding var query: String
    let state: CommandPaletteLoadState
    var smartLists: [SavedSearchSnapshot] = []
    let onLoad: () -> Void
    var onOpenSmartList: (SavedSearchSnapshot) -> Void = { _ in }
    let onExecuteTarget: (CommandTargetSnapshot) -> Void
    let onClose: () -> Void

    @State private var selectedTargetID: String?

    var body: some View {
        MainFileActionSheetContainer(title: "Command Palette", pageID: "S2-15") {
            commandSearchField
            commandStatus
            commandSections
            footer
        }
        .frame(width: 640)
        .task {
            onLoad()
        }
        .onAppear {
            selectFirstExecutableTargetIfNeeded()
        }
        .onChange(of: state.snapshot?.sections) { _, _ in
            selectFirstExecutableTargetIfNeeded()
        }
        .onSubmit(of: .text) {
            executeSelectedTarget()
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            moveSelectedTarget(offset: -1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            moveSelectedTarget(offset: 1)
            return .handled
        }
        .accessibilityIdentifier("S2-15-C2-11-command-palette")
    }

    private var commandSearchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Type a command or search...", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S2-15-C2-11-search-field")
            Text("Esc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: query) { _, _ in onLoad() }
    }

    @ViewBuilder
    private var commandStatus: some View {
        if state.isLoading {
            Text("Loading commands...")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-15-C2-11-loading")
        }
        if let error = state.errorMapping {
            Text("\(error.userMessage) \(error.suggestedAction)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-15-C2-11-error")
        }
        if state.snapshot?.isEmpty == true {
            Text(noResultsMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-15-C2-11-empty")
        }
    }

    private var commandSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                commandIndexSections
                commandPaletteSmartListSection
            }
        }
        .frame(maxHeight: 360)
    }

    private var commandIndexSections: some View {
        ForEach(state.snapshot?.sections ?? []) { section in
            if !section.targets.isEmpty {
                CommandPaletteSectionView(
                    section: section,
                    selectedTargetID: selectedTargetID,
                    onSelect: { selectedTargetID = $0.id },
                    onExecute: onExecuteTarget
                )
            }
        }
    }

    private var commandPaletteSmartListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Lists")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(smartListTargets) { target in
                Button {
                    onOpenSmartList(target.savedSearch)
                } label: {
                    Label(target.title, systemImage: target.systemImage)
                }
                .help(target.helpText)
                .accessibilityIdentifier(target.accessibilityIdentifier)
            }
            if smartListTargets.isEmpty {
                Text(emptySmartListMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("S2-15-C2-04-smart-list-empty")
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var smartListTargets: [CommandPaletteSmartListTarget] {
        CommandPaletteSmartListTarget.matching(smartLists, query: query)
    }

    private var emptySmartListMessage: String {
        smartLists.isEmpty ? "No Smart Lists saved." : "No Smart Lists match this search."
    }

    private var noResultsMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No commands available." : "No commands found for \"\(trimmed)\". Try \"import\", \"tag\", or \"settings\"."
    }

    private var executableTargets: [CommandTargetSnapshot] {
        state.snapshot?.sections.flatMap(\.targets).filter(\.isExecutable) ?? []
    }

    private func selectFirstExecutableTargetIfNeeded() {
        let targets = executableTargets
        if selectedTargetID.flatMap({ id in targets.first { $0.id == id } }) != nil { return }
        selectedTargetID = targets.first?.id
    }

    private func executeSelectedTarget() {
        guard let target = selectedTargetID.flatMap({ id in executableTargets.first { $0.id == id } }) else {
            onLoad()
            return
        }
        onExecuteTarget(target)
    }

    private func moveSelectedTarget(offset: Int) {
        selectedTargetID = CommandPaletteSelectionRouting.nextSelectedID(
            currentID: selectedTargetID,
            targets: state.snapshot?.sections.flatMap(\.targets) ?? [],
            offset: offset
        )
    }
}

private struct CommandPaletteSectionView: View {
    let section: CommandPaletteSectionSnapshot
    let selectedTargetID: String?
    let onSelect: (CommandTargetSnapshot) -> Void
    let onExecute: (CommandTargetSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(section.targets) { target in
                CommandPaletteResultRow(
                    target: target,
                    isSelected: target.id == selectedTargetID,
                    onSelect: { onSelect(target) },
                    onExecute: { onExecute(target) }
                )
            }
        }
    }
}

private struct CommandPaletteResultRow: View {
    let target: CommandTargetSnapshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onExecute: () -> Void

    var body: some View {
        Button {
            onSelect()
            onExecute()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let shortcut = target.shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if target.requiresConfirmation {
                    Text("Requires confirmation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .disabled(!target.isExecutable)
        .opacity(target.disabled ? 0.55 : 1)
        .onHover { hovering in
            if hovering { onSelect() }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("S2-15-C2-11-command-\(target.id)")
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.16))
        }
    }

    private var subtitleText: String {
        target.disabledReason ?? target.subtitle ?? target.action.rawValue
    }

    private var accessibilityLabel: String {
        [target.title, subtitleText, target.shortcut, target.confirmationLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var accessibilityHint: String {
        target.isExecutable ? "Press Enter to run this command." : "Command is unavailable."
    }

    private var systemImage: String {
        switch target.kind {
        case .navigation:
            "arrow.turn.down.right"
        case .smartList:
            "line.3.horizontal.decrease.circle"
        case .fileCandidate:
            "doc"
        case .recentCommand:
            "clock"
        case .command:
            target.requiresConfirmation ? "exclamationmark.triangle" : "command"
        }
    }
}
