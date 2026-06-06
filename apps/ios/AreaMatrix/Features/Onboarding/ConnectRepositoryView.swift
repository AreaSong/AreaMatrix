import SwiftUI
import UniformTypeIdentifiers

struct ConnectRepositoryView: View {
    @ObservedObject var model: ConnectRepositoryModel
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                actionsSection
                recentSection
                safetySection
            }
            .connectRepositoryListStyle()
            .navigationTitle("Connect Repository")
            .toolbar {
                Button("Help") {}
            }
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: handleFolderSelection
            )
            .task {
                await model.loadRecentRepositories()
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("连接 AreaMatrix 资料库")
                    .font(.title2.weight(.semibold))
                Text("选择一个已有的 AreaMatrix 文件夹。AreaMatrix 不会在你确认前移动、删除或覆盖文件。")
                    .foregroundStyle(.secondary)
                Text("推荐使用 iCloud Drive，这样可以和 Mac 共用同一个资料库。")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showingFolderPicker = true
            } label: {
                actionLabel(
                    title: primaryButtonTitle,
                    subtitle: "从 iCloud Drive 中选择包含 .areamatrix 的文件夹。",
                    systemImage: "icloud"
                )
            }
            .disabled(model.isChecking)
            .accessibilityLabel(primaryButtonTitle)

            Button {
                showingFolderPicker = true
            } label: {
                actionLabel(
                    title: "Choose Folder...",
                    subtitle: "选择 Files app 中可访问的位置。某些第三方云盘可能只提供临时访问。",
                    systemImage: "folder"
                )
            }
            .disabled(model.isChecking)
            .accessibilityLabel("Choose Folder")

            if let error = model.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if model.latestValidation?.isThirdPartyCloudPath == true {
                Label("同步行为由所选云盘提供商决定。", systemImage: "cloud")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recentRepositories.isEmpty {
            Section("Recent Repositories") {
                ForEach(model.recentRepositories) { repository in
                    Button {
                        Task { await model.reconnect(repository) }
                    } label: {
                        recentRepositoryRow(repository)
                    }
                    .disabled(model.isChecking)
                    .accessibilityLabel(accessibilityLabel(for: repository))
                }
            }
        }
    }

    private var safetySection: some View {
        Section {
            Text("连接前只读取目录结构；初始化或接管目录会在下一步单独确认。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryButtonTitle: String {
        model.isChecking ? "Checking..." : "Connect iCloud Repository"
    }

    private func actionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    if model.isChecking && title == "Checking..." {
                        ProgressView()
                    }
                }
                .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func recentRepositoryRow(_ repository: RecentRepository) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.displayName)
                    .font(.headline)
                Text(repository.pathDisplay)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(repository.lastOpenedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusText(for: repository.accessStatus))
                .font(.footnote.weight(.medium))
                .foregroundStyle(statusColor(for: repository.accessStatus))
        }
    }

    private func statusText(for status: RecentRepository.AccessStatus) -> String {
        status == .available ? "Open" : "Reconnect"
    }

    private func statusColor(for status: RecentRepository.AccessStatus) -> Color {
        status == .available ? .secondary : .orange
    }

    private func accessibilityLabel(for repository: RecentRepository) -> String {
        switch repository.accessStatus {
        case .available:
            "Open recent repository \(repository.displayName)"
        case .expired:
            "Reconnect recent repository \(repository.displayName), access expired"
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task { await model.connectSelectedURL(url) }
        case .failure:
            model.cancelSystemPicker()
        }
    }
}

private extension View {
    @ViewBuilder
    func connectRepositoryListStyle() -> some View {
        #if os(iOS)
            listStyle(.insetGrouped)
        #else
            listStyle(.inset)
        #endif
    }
}
