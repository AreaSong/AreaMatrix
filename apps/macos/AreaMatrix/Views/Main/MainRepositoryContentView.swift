import SwiftUI
import UniformTypeIdentifiers

enum MainRepositoryContentState: Equatable, Sendable {
    case empty
    case list
}

struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL]) -> Void
    let onOpenSettings: () -> Void
    let onRetryCurrentList: () -> Void
    @State private var selectedCategory: String = "inbox"
    @State private var filterText: String = ""
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                listPane
                Divider()
                detailPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Menu {
                Text(opening.config.repoPath)
                Button("Settings", action: onOpenSettings)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text("AreaMatrix")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.headline)
            }
            .accessibilityLabel("Repository AreaMatrix")
            Spacer()
            TextField("Filter current list", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Import...", action: onImport)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            ForEach(opening.tree.sidebarNodes) { node in
                sidebarRow(node)
                    .tag(node.slug)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
        .onChange(of: opening.tree.sidebarNodes) { _, nodes in
            selectedCategory = Self.defaultSelectedCategory(from: nodes)
        }
    }

    private func sidebarRow(_ node: RepositoryTreeNodeSnapshot) -> some View {
        HStack {
            Text(node.displayName)
            Spacer()
            Text("\(node.totalFileCount)")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(node.displayName) \(node.totalFileCount)")
    }

    private static func defaultSelectedCategory(from nodes: [RepositoryTreeNodeSnapshot]) -> String {
        nodes.first { $0.slug == "inbox" }?.slug ?? nodes.first?.slug ?? "__root__"
    }

    private var statusText: String {
        state == .empty ? "Idle" : "Synced"
    }

    private var selectedListTitle: String {
        selectedSidebarNode.displayName
    }

    private var selectedSidebarNode: RepositoryTreeNodeSnapshot {
        opening.tree.sidebarNodes.first { $0.slug == selectedCategory } ??
            opening.tree.sidebarNodes.first ??
            opening.tree
    }

    init(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL]) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onRetryCurrentList: @escaping () -> Void = {}
    ) {
        self.opening = opening
        self.state = state
        self.onImport = onImport
        self.onDropImport = onDropImport
        self.onOpenSettings = onOpenSettings
        self.onRetryCurrentList = onRetryCurrentList
        _selectedCategory = State(initialValue: Self.defaultSelectedCategory(from: opening.tree.sidebarNodes))
    }

    @ViewBuilder
    private var listPane: some View {
        if let error = opening.currentCategoryListError {
            currentListErrorPane(error)
        } else {
            listContentPane
        }
    }

    @ViewBuilder
    private var listContentPane: some View {
        switch state {
        case .empty:
            VStack(spacing: 14) {
                Text("这里还没有文件")
                    .font(.title2.weight(.semibold))
                Text("把文件拖到这里，AreaMatrix 会自动分类、命名并记录改动。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Import...", action: onImport)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                FileDropAdapter(onDrop: onDropImport).handle(providers)
            }
            .accessibilityElement(children: .contain)
        case .list:
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedListTitle)
                    .font(.title3.weight(.semibold))
                Text("\(opening.tree.totalFileCount) files")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                ForEach(opening.tree.sidebarNodes) { node in
                    HStack {
                        Text(node.displayName)
                        Spacer()
                        Text("\(node.totalFileCount)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func currentListErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current list cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retry", action: onRetryCurrentList)
                DisclosureGroup("Technical Details") {
                    Text(error.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择一个文件查看详情")
                .font(.headline)
            Text("文件的元数据、改动时间线和伴生笔记会显示在这里。")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }

}
