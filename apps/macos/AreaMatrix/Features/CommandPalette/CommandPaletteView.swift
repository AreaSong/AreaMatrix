import AreaMatrixUIFoundation
import SwiftUI

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
        AreaMatrixActionSheetContainer(title: L10n.string("Command Palette"), pageID: "command-palette") {
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
        .accessibilityIdentifier("command-palette-command-index-command-palette")
    }

    private var commandSearchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(L10n.string("Type a command or search..."), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("command-palette-command-index-search-field")
            Text(L10n.string("Esc"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: query) { _, _ in onLoad() }
    }

    @ViewBuilder
    private var commandStatus: some View {
        if state.isLoading {
            Text(L10n.string("Loading commands..."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("command-palette-command-index-loading")
        }
        if let error = state.errorMapping {
            Text(L10n.format("commandPalette.error.detail", error.userMessage, error.suggestedAction))
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("command-palette-command-index-error")
        }
        if state.snapshot?.isEmpty == true {
            Text(noResultsMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("command-palette-command-index-empty")
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
            Text(L10n.string("Smart Lists"))
                .font(.caption)
                .foregroundStyle(.secondary)
            smartListButtons
        }
    }

    @ViewBuilder
    private var smartListButtons: some View {
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
                .accessibilityIdentifier("command-palette-smart-list-smart-list-empty")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.string("Close"), action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var smartListTargets: [CommandPaletteSmartListTarget] {
        CommandPaletteSmartListTarget.matching(smartLists, query: query)
    }

    private var emptySmartListMessage: String {
        smartLists.isEmpty
            ? L10n.string("No Smart Lists saved.")
            : L10n.string("No Smart Lists match this search.")
    }

    private var noResultsMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? L10n.string("No commands available.")
            : L10n.format("commandPalette.noResults.query", trimmed)
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
            rowContent
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
        }
        .buttonStyle(.plain)
        .disabled(!target.isExecutable)
        .opacity(target.isExecutable ? 1 : 0.55)
        .onHover { hovering in
            if hovering { onSelect() }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("command-palette-command-index-command-\(target.id)")
    }

    private var rowContent: some View {
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
                Text(L10n.string("Requires confirmation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.16))
        }
    }

    private var subtitleText: String {
        target.effectiveDisabledReason ?? target.subtitle ?? target.action.displayName
    }

    private var accessibilityLabel: String {
        [target.title, subtitleText, target.shortcut, target.confirmationLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var accessibilityHint: String {
        target.isExecutable
            ? L10n.string("Press Enter to run this command.")
            : L10n.string("Command is unavailable.")
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
