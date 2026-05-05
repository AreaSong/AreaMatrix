import SwiftUI

enum MainRepositoryContentState: Equatable, Sendable {
    case empty
    case list
}

struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState

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
            Label("AreaMatrix", systemImage: "folder")
                .font(.headline)
            Text(opening.config.repoPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            TextField("Filter current list", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .disabled(true)
            Button("Import...") {}
                .disabled(true)
            Button {
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
            .disabled(true)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sidebar: some View {
        List(opening.tree.sidebarNodes) { node in
            HStack {
                Text(node.displayName)
                Spacer()
                Text("\(node.totalFileCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    @ViewBuilder
    private var listPane: some View {
        switch state {
        case .empty:
            VStack(spacing: 14) {
                Text("这里还没有文件")
                    .font(.title2.weight(.semibold))
                Text("把文件拖到这里，AreaMatrix 会自动分类、命名并记录改动。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Import...") {
                    // Import is owned by later S1-17/S1-18/S1-19 tasks; keep the visible affordance inert here.
                }
                    .disabled(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var statusText: String {
        state == .empty ? "Idle" : "Synced"
    }

    private var selectedListTitle: String {
        opening.tree.sidebarNodes.first?.displayName ?? opening.tree.displayName
    }
}

private extension RepositoryTreeNodeSnapshot {
    var sidebarNodes: [RepositoryTreeNodeSnapshot] {
        children.isEmpty ? [self] : children
    }
}
