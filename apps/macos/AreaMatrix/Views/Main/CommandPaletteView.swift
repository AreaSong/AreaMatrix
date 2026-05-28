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
                .accessibilityIdentifier("S2-15-C2-04-smart-list-empty")
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
        return trimmed.isEmpty
            ? "No commands available."
            : "No commands found for \"\(trimmed)\". Try \"import\", \"tag\", or \"settings\"."
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
        .accessibilityIdentifier("S2-15-C2-11-command-\(target.id)")
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
                Text("Requires confirmation")
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
        target.effectiveDisabledReason ?? target.subtitle ?? target.action.rawValue
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
