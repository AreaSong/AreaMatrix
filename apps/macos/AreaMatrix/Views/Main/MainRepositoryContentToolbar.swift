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

extension MainRepositoryContentView {
    var toolbar: some View {
        HStack(spacing: 14) {
            Menu {
                Text(opening.config.repoPath)
                Button("Settings", action: onOpenSettings)
            } label: {
                HStack(spacing: 5) {
                    MainRepositoryToolbarLogo()
                    Text("AreaMatrix")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.headline)
            }
            .accessibilityLabel(L10n.string("Repository AreaMatrix"))
            Spacer()
            TextField("Search files", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isSearchFieldFocused)
                .onExitCommand {
                    handleSearchEscape()
                }
                .onSubmit {
                    fileListModel.enterSearch(context: .toolbar)
                }
                .accessibilityIdentifier("search-index-status-search-field")
            Picker("Mode", selection: $searchMode) {
                ForEach(SearchModeSnapshot.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .accessibilityIdentifier("semantic-search-semantic-search-core-search-mode")
            Picker("Scope", selection: $searchScope) {
                ForEach(SearchScopeSnapshot.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            Picker("Sort", selection: $searchSort) {
                ForEach(SearchSortSnapshot.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
            .frame(width: 170)
            searchFiltersButton
            Button(action: openUndoHistoryFromToolbar) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Undo History")
            .accessibilityLabel(L10n.string("Undo History"))
            .accessibilityIdentifier("undo-history-undo-action-log-toolbar-open-history")
            Button("Import...", action: onImport)
                .disabled(opening.isReadOnly)
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
            beginCommandFindSearch()
            return .handled
        }
        .onKeyPress("k", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            toggleCommandPalette()
            return .handled
        }
    }

    private var statusText: String {
        state == .empty ? L10n.string("Idle") : L10n.string("Synced")
    }
}
