import SwiftUI
import UniformTypeIdentifiers

struct ConnectRepositoryView: View {
    @ObservedObject var model: ConnectRepositoryModel
    @StateObject private var routeCoordinator = ConnectRepositoryRouteCoordinator()
    @State private var showingFolderPicker = false
    @State private var showingRepositoryHelp = false

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
                Button("Help") {
                    showingRepositoryHelp = true
                }
            }
            .sheet(isPresented: $showingRepositoryHelp) {
                ConnectRepositoryHelpView()
            }
            .navigationDestination(isPresented: $routeCoordinator.isPresented) {
                routeDestination
            }
            .onChange(of: model.route) { _, route in
                routeCoordinator.update(route)
            }
            .onChange(of: routeCoordinator.isPresented) { _, isPresented in
                if !isPresented {
                    routeCoordinator.dismiss()
                    model.dismissRoute()
                }
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

    @ViewBuilder
    private var routeDestination: some View {
        if let route = routeCoordinator.activeRoute {
            ConnectRepositoryRouteDestinationView(route: route)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("连接 AreaMatrix 资料库")
                    .font(.title2.weight(.semibold))
                Text(
                    "选择一个已有的 AreaMatrix 文件夹。"
                        + "AreaMatrix 不会在你确认前移动、删除或覆盖文件。"
                )
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
                Task {
                    if await model.connectICloudRepository() {
                        showingFolderPicker = true
                    }
                }
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
                    subtitle: "选择 Files app 中可访问的位置。"
                        + "某些第三方云盘可能只提供临时访问。",
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
            if let cloudState = model.latestCloudState, cloudState.shouldDisplayOnConnectPage {
                Label(cloudStatusText(for: cloudState), systemImage: "cloud")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(cloudAccessibilityLabel(for: cloudState))
            } else if model.latestValidation?.isThirdPartyCloudPath == true {
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
                        Task {
                            if await model.reconnect(repository) {
                                showingFolderPicker = true
                            }
                        }
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
                if repository.accessStatus == .expired {
                    Text("Access expired")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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

    private func cloudStatusText(for state: MobileCloudStorageState) -> String {
        if state.requiresReconnect || state.permissionState == .accessExpired {
            return "iCloud 访问凭证已失效，需要重新连接。"
        }
        if state.permissionState == .permissionDenied {
            return "iCloud 权限不足，请重新授权。"
        }
        if state.placeholderState == .placeholder {
            return "iCloud 文件夹尚未下载，请在 Files 中下载后重试。"
        }
        if state.recommendedAction == .retryStatusCheck {
            return "iCloud 状态暂时不可确认，可稍后重试。"
        }
        if state.providerKind != .local || state.risk != .noRisk {
            return state.statusSummary.isEmpty ? "同步行为由所选云盘提供商决定。" : state.statusSummary
        }
        return "同步行为由所选云盘提供商决定。"
    }

    private func cloudAccessibilityLabel(for state: MobileCloudStorageState) -> String {
        "Cloud status, \(cloudStatusText(for: state))"
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

@MainActor
final class ConnectRepositoryRouteCoordinator: ObservableObject {
    @Published private(set) var activeRoute: MobileRepositoryConnectionRoute?
    @Published var isPresented = false

    func update(_ route: MobileRepositoryConnectionRoute?) {
        activeRoute = route
        isPresented = route != nil
    }

    func dismiss() {
        activeRoute = nil
        isPresented = false
    }
}

struct ConnectRepositoryRouteDestinationContent: Equatable {
    var title: String
    var systemImage: String
    var primaryText: String
    var pathText: String?

    init(route: MobileRepositoryConnectionRoute) {
        switch route {
        case let .mobileLibrary(connection):
            title = "Mobile Library"
            systemImage = "folder"
            primaryText = "Repository connected."
            pathText = connection.validation.repoPath
        case let .repositoryInitConfirm(candidate):
            title = "Initialize Repository"
            systemImage = "checkmark.shield"
            primaryText = "Review this empty folder before AreaMatrix creates metadata."
            pathText = candidate.validation.repoPath
        case let .repositoryAdoptConfirm(candidate):
            title = "Adopt Repository"
            systemImage = "folder.badge.plus"
            primaryText = "Review this folder before AreaMatrix adopts it."
            pathText = candidate.validation.repoPath
        case let .iCloudPermission(error):
            title = "iCloud Permission"
            systemImage = "icloud.slash"
            primaryText = error.message
            pathText = nil
        }
    }
}

struct ConnectRepositoryRouteDestinationView: View {
    private let route: MobileRepositoryConnectionRoute
    private let mobileLibraryBridge: any MobileLibraryCoreBridge
    private let content: ConnectRepositoryRouteDestinationContent

    init(
        route: MobileRepositoryConnectionRoute,
        mobileLibraryBridge: any MobileLibraryCoreBridge = LiveMobileRepositoryCoreBridge()
    ) {
        self.route = route
        self.mobileLibraryBridge = mobileLibraryBridge
        content = ConnectRepositoryRouteDestinationContent(route: route)
    }

    var body: some View {
        switch route {
        case let .mobileLibrary(connection):
            MobileLibraryView(connection: connection, bridge: mobileLibraryBridge)
        case .repositoryInitConfirm, .repositoryAdoptConfirm, .iCloudPermission:
            List {
                Section {
                    Label(content.primaryText, systemImage: content.systemImage)
                    if let pathText = content.pathText {
                        Text(pathText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .connectRepositoryListStyle()
            .navigationTitle(content.title)
        }
    }
}

struct ConnectRepositoryHelpContent: Equatable {
    var title: String
    var rows: [String]

    static let repositoryHelp = ConnectRepositoryHelpContent(
        title: "Repository Help",
        rows: [
            "A repository is a normal folder that contains AreaMatrix metadata.",
            "AreaMatrix only reads the folder structure before you confirm initialization or adoption.",
            "iCloud Drive lets this iOS app share the same repository folder with your Mac."
        ]
    )
}

struct ConnectRepositoryHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let content = ConnectRepositoryHelpContent.repositoryHelp

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(content.rows, id: \.self) { row in
                        Text(row)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .connectRepositoryListStyle()
            .navigationTitle(content.title)
            .toolbar {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
