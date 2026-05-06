import SwiftUI

struct ImportProgressView: View {
    let state: ImportProgressRouteState
    let onReturnToRepository: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.toolbarText)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(state.titleText)
                    .font(.headline)
                Text(state.bannerText)
                Text("当前：\(state.currentPath)")
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if showsDetails {
                VStack(alignment: .leading, spacing: 6) {
                    Text("资料库：\(state.repoPath)")
                        .textSelection(.enabled)
                    Text("已完成 \(state.completed)，失败 \(state.failed)，剩余 \(state.remaining)")
                    if let errorMapping = state.errorMapping {
                        Text("错误级别：\(errorMapping.severity.rawValue)")
                        Text("建议操作：\(errorMapping.suggestedAction)")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(state.detailsButtonTitle) {
                    showsDetails.toggle()
                }
                if state.isFailed {
                    Button("Back to repository", action: onReturnToRepository)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
    }
}
