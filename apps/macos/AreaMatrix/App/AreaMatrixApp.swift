import AppKit
import Foundation
import SwiftUI

struct AppShellModel: Equatable, Sendable {
    var statusText = "Onboarding configuration router"
}

protocol AppSettingsReading {
    func configuredRepoPath() -> String?
}

protocol AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String)
}

struct UserDefaultsAppSettingsReader: AppSettingsReading {
    private let defaults: UserDefaults
    private let repoPathKey: String

    init(defaults: UserDefaults = .standard, repoPathKey: String = "AreaMatrix.repoPath") {
        self.defaults = defaults
        self.repoPathKey = repoPathKey
    }

    func configuredRepoPath() -> String? {
        guard let value = defaults.string(forKey: repoPathKey) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UserDefaultsAppSettingsReader: AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String) {
        defaults.set(repoPath, forKey: repoPathKey)
    }
}

protocol WelcomeHelpOpening {
    func openWelcomeHelp() throws
}

protocol RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL?
}

struct LocalWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/product/prd.md")

        guard FileManager.default.fileExists(atPath: docsURL.path) else {
            throw WelcomeHelpError.helpDocumentUnavailable
        }

        NSWorkspace.shared.open(docsURL)
    }
}

struct NSOpenPanelRepositoryDirectoryPicker: RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a repository folder."

        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum WelcomeHelpError: Error, Equatable, Sendable {
    case helpDocumentUnavailable
}

@main
struct AreaMatrixApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .windowResizability(.contentMinSize)
    }
}

struct MainLoadingView: View {
    let repoPath: String
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Opening repository...")
                .font(.title2.weight(.semibold))
            Text(repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct MainRepoErrorView: View {
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository cannot be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text(mapping?.userMessage ?? "AreaMatrix could not open the selected repository.")
            Text(repoPath)
        } actions: {
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
    }
}

struct DBRepairConfirmView: View {
    let repoPath: String
    let scanSession: ScanSessionSnapshot?
    let mapping: CoreErrorMappingSnapshot?
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository metadata needs repair", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(mapping?.userMessage ?? "AreaMatrix found incomplete or damaged .areamatrix metadata.")
            Text(
                "Repair only affects .areamatrix/ metadata; user files are not moved, renamed, deleted, or overwritten."
            )
            if let scanSession {
                Text("Last scan: \(scanSession.status.rawValue), inserted \(scanSession.inserted).")
            }
            Text(repoPath)
        } actions: {
            Button("Choose another folder", action: onChooseAnotherFolder)
        }
    }
}

struct RepositoryReadyView: View {
    let config: RepoConfigSnapshot

    var body: some View {
        ContentUnavailableView {
            Label("Repository ready", systemImage: "checkmark.circle")
        } description: {
            Text(config.repoPath)
            Text("Locale: \(config.locale)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConfirmInitStepView: View {
    let draft: RepositoryInitializationDraft
    let onBack: () -> Void
    let onChangePath: () -> Void
    let onCreateEmpty: () -> Void
    let onCancelSetup: () -> Void

    @State private var isCancelConfirmationPresented = false

    private let createItems = [
        "docs/", "code/", "design/", "finance/", "media/", "inbox/",
        ".areamatrix/index.db", ".areamatrix/ignore.yaml",
        ".areamatrix/generated/", ".areamatrix/staging/",
    ]

    private let adoptItems = [
        "创建 .areamatrix/ 内部目录",
        "创建 .areamatrix/ignore.yaml",
        "创建本地索引数据库",
        "扫描现有文件和文件夹",
        "将已有文件标记为 adopted / indexed",
        "生成 .areamatrix/generated/root.md",
    ]

    private let safetyItems = [
        "不移动已有文件",
        "不重命名已有文件",
        "不删除已有文件",
        "不覆盖已有 README.md",
        "不修改已有项目目录结构",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    pathBox
                    planSection
                    safetySection
                    iCloudWarning
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .confirmationDialog("退出设置？", isPresented: $isCancelConfirmationPresented) {
            Button("Quit", role: .destructive, action: onCancelSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AreaMatrix 不会写入资料库，下次启动可重新选择。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isCreateEmpty ? "将创建新的 AreaMatrix 资料库" : "将接管已有目录")
                .font(.system(size: 34, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("确认后才会开始写入 .areamatrix/ 元数据。")
                .font(.title3)
        }
    }

    private var pathBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资料库路径")
                .font(.headline)
            Text(draft.validation.repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var planSection: some View {
        InitPlanList(title: isCreateEmpty ? "将创建" : "将执行", items: isCreateEmpty ? createItems : adoptItems)
    }

    private var safetySection: some View {
        InitPlanList(title: "不会执行", items: safetyItems, iconName: "checkmark.shield")
    }

    @ViewBuilder
    private var iCloudWarning: some View {
        if draft.validation.isICloudPath {
            Label(
                "该路径位于 iCloud 管理范围内，请确认文件已在本机可用。",
                systemImage: "icloud"
            )
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onBack)
            Button("Cancel Setup") {
                isCancelConfirmationPresented = true
            }
            Button("Change Path", action: onChangePath)
            Spacer()
            Button(isCreateEmpty ? "Create Repository" : "Adopt Folder", action: onCreateEmpty)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isCreateEmpty)
        }
        .frame(maxWidth: 680)
        .padding(.top, 18)
    }

    private var isCreateEmpty: Bool {
        draft.mode == .createEmpty && draft.validation.recommendedMode == .createEmpty
    }
}

private struct InitPlanList: View {
    let title: String
    let items: [String]
    var iconName = "plus.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: iconName)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.callout)
                        .accessibilityLabel(item)
                }
            }
        }
    }
}
