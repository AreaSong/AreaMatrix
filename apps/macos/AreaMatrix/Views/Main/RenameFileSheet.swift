import SwiftUI

struct RenameFileSheet: View {
    let file: FileEntrySnapshot?
    let onCancel: () -> Void
    @State private var newName: String

    init(file: FileEntrySnapshot?, onCancel: @escaping () -> Void) {
        self.file = file
        self.onCancel = onCancel
        _newName = State(initialValue: file?.currentName ?? "")
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Rename File", pageID: "S1-33") {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    metadataRow("Current name", file.currentName)
                    metadataRow("Location", file.categoryPathDisplay)
                    metadataRow("Storage mode", file.storageMode)
                    TextField("New name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Only the file name changes. Category and notes stay attached to this file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    actionButtons()
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private var validationMessage: String? {
        guard let file else { return nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "File name is required" }
        if trimmed.contains(":") { return "File name cannot contain \":\"" }
        if trimmed == file.currentName { return "Enter a different file name" }
        return nil
    }

    private func actionButtons() -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Rename") {}
                .disabled(true)
                .keyboardShortcut(.defaultAction)
        }
    }
}
