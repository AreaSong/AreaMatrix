import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    var listPane: some View {
        if let error = currentListError {
            currentListErrorPane(error)
        } else {
            listContentPane
        }
    }

    private var selectedListTitle: String {
        selectedSidebarRow.displayName
    }

    private var currentListError: CoreErrorMappingSnapshot? {
        state == .list ? fileListModel.errorMapping : opening.currentCategoryListError
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
                    .disabled(opening.isReadOnly)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(ImportDropTargetModifier(
                target: .autoClassify,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
            .accessibilityElement(children: .contain)
        case .list:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedListTitle)
                        .font(.title3.weight(.semibold))
                    Text(listCountText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    listLoadingIndicator
                }
                Divider()
                statusBanner
                fileTable
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(ImportDropTargetModifier(
                target: selectedSidebarRow.importDropTarget,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
        }
    }

    @ViewBuilder
    private var listLoadingIndicator: some View {
        if let loadingStatus = fileListModel.loadingStatusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fileListModel.loadingAccessibilityText ?? "Loading files")
        }
    }
}
