import SwiftUI

struct InitDoneStepView: View {
    let result: RepositoryInitializationResult
    let errorMapping: CoreErrorMappingSnapshot?
    let onOpenRepository: () -> Void
    let onOpenInFinder: () async -> Void

    @State private var isOpeningFinder = false

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            header

            VStack(spacing: 20) {
                pathBox
                summarySection
                openErrorSection
            }
            .frame(maxWidth: 440)

            footer
        }
        .areaMatrixOnboardingPanel()
    }

    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: "checkmark.circle.fill",
            tint: .green,
            title: "资料库已准备好",
            subtitle: "AreaMatrix 已完成初始化。\n你现在可以浏览资料库，或把文件拖进窗口开始归档。"
        )
    }

    private var pathBox: some View {
        AreaMatrixPathBox(path: result.repoPath)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summaryItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaMatrixGlassCard()
        }
    }

    @ViewBuilder
    private var openErrorSection: some View {
        if let errorMapping {
            TintedOutlinedStatusBanner(tint: .red) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("无法打开资料库", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorMapping.userMessage)
                    Text(errorMapping.suggestedAction)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("在 Finder 中打开") {
                Task {
                    await openInFinder()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isOpeningFinder)

            if isOpeningFinder {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(action: onOpenRepository) {
                Text(errorMapping == nil ? "打开资料库" : "重试")
                    .font(.body.weight(.medium))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 440)
        .padding(.top, 16)
    }

    @MainActor
    private func openInFinder() async {
        guard !isOpeningFinder else { return }

        isOpeningFinder = true
        defer {
            isOpeningFinder = false
        }
        await onOpenInFinder()
    }

    private var summaryItems: [String] {
        switch result.mode {
        case .createEmpty:
            ["已创建默认分类", "已创建本地索引", "已启用自动概览"]
        case .adoptExisting:
            [
                "已建立本地索引",
                "已扫描现有文件",
                "已保留原有目录结构",
                "已生成内部概览"
            ]
        }
    }
}
