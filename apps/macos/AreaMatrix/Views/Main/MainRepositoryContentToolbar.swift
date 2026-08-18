import AppKit
import SwiftUI

private enum MainRepositoryToolbarAssets {
    static let darkLogo = resizedLogo(named: "AreaMatrixLogoMarkDark")
    static let lightLogo = resizedLogo(named: "AreaMatrixLogoMarkLight")

    private static func resizedLogo(named name: String) -> NSImage {
        guard let source = NSImage(named: name),
              let logo = source.copy() as? NSImage
        else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }

        logo.size = NSSize(width: 18, height: 18)
        return logo
    }
}

private struct MainRepositoryToolbarLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: colorScheme == .dark
            ? MainRepositoryToolbarAssets.darkLogo
            : MainRepositoryToolbarAssets.lightLogo)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

struct MainRepositoryToolbar: View {
    let repoPath: String
    let isReadOnly: Bool
    let isEmpty: Bool
    @Binding var filterText: String
    @Binding var searchMode: SearchModeSnapshot
    @Binding var searchScope: SearchScopeSnapshot
    @Binding var searchSort: SearchSortSnapshot
    @FocusState.Binding var isSearchFieldFocused: Bool
    let searchFiltersButton: AnyView
    let onImport: () -> Void
    let onOpenSettings: () -> Void
    let onSearchExit: () -> Void
    let onSearchSubmit: () -> Void
    let onCommandFind: () -> Void
    let onCommandPalette: () -> Void
    let onOpenUndoHistory: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                Text(repoPath)
                Button(L10n.string("Settings"), action: onOpenSettings)
            } label: {
                HStack(spacing: 5) {
                    MainRepositoryToolbarLogo()
                    Text(L10n.string("AreaMatrix"))
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.headline)
            }
            .accessibilityLabel(L10n.string("Repository AreaMatrix"))
            Spacer()
            TextField(L10n.string("Search files"), text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isSearchFieldFocused)
                .onExitCommand {
                    onSearchExit()
                }
                .onSubmit {
                    onSearchSubmit()
                }
                .accessibilityIdentifier("search-index-status-search-field")
            Picker(L10n.string("Mode"), selection: $searchMode) {
                ForEach(SearchModeSnapshot.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .accessibilityIdentifier("semantic-search-semantic-search-core-search-mode")
            Picker(L10n.string("Scope"), selection: $searchScope) {
                ForEach(SearchScopeSnapshot.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            Picker(L10n.string("Sort"), selection: $searchSort) {
                ForEach(SearchSortSnapshot.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
            .frame(width: 170)
            searchFiltersButton
            Button(action: onOpenUndoHistory) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Undo History"))
            .accessibilityLabel(L10n.string("Undo History"))
            .accessibilityIdentifier("undo-history-undo-action-log-toolbar-open-history")
            Button(L10n.string("Import..."), action: onImport)
                .disabled(isReadOnly)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.string("Settings"))
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
        .onKeyPress("f", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            onCommandFind()
            return .handled
        }
        .onKeyPress("k", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            onCommandPalette()
            return .handled
        }
    }

    private var statusText: String {
        isEmpty ? L10n.string("Idle") : L10n.string("Synced")
    }
}
