import SwiftUI

struct ChangeCategorySheet: View {
    let file: FileEntrySnapshot?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let onCancel: () -> Void
    @State private var targetCategory: String

    init(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot],
        onCancel: @escaping () -> Void
    ) {
        self.file = file
        self.categoryRows = categoryRows
        self.onCancel = onCancel
        _targetCategory = State(initialValue: Self.defaultTargetCategory(for: file, categoryRows: categoryRows))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Change Category", pageID: "S1-35") {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    metadataRow("Name", file.currentName)
                    metadataRow("Current category", file.categoryPathDisplay)
                    metadataRow("Storage mode", file.storageMode)
                    Picker("Target category", selection: $targetCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    metadataRow("Target path", targetPath(for: file))
                    Text(changeCategoryMessage(for: file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    actionButtons()
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private func targetPath(for file: FileEntrySnapshot) -> String {
        "\(targetCategory)/\(file.currentName)"
    }

    private func changeCategoryMessage(for file: FileEntrySnapshot) -> String {
        targetCategory == file.category ? "Choose a different category" : "Confirm the target in S1-35."
    }

    private func actionButtons() -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Change Category") {}
                .disabled(true)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var availableCategories: [String] {
        MainFileActionCategoryOptions.availableCategories(file: file, categoryRows: categoryRows)
    }

    private static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        MainFileActionCategoryOptions.defaultTargetCategory(for: file, categoryRows: categoryRows)
    }
}
