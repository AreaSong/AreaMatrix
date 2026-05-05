import SwiftUI

struct DeleteFileConfirmSheet: View {
    let file: FileEntrySnapshot?
    let onCancel: () -> Void
    @State private var isConfirmed = false

    var body: some View {
        MainFileActionSheetContainer(title: "Move File to Trash?", pageID: "S1-34") {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AreaMatrix will move this file to the system Trash and keep a change-log record.")
                        .foregroundStyle(.secondary)
                    metadataRow("Name", file.currentName)
                    metadataRow("Location", file.path)
                    metadataRow("Storage mode", file.storageMode)
                    metadataRow("Status", file.statusDisplay)
                    Toggle("我理解该文件会被移到系统废纸篓", isOn: $isConfirmed)
                    actionButtons()
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private func actionButtons() -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Move to Trash", role: .destructive) {}
                .disabled(!isConfirmed)
        }
    }
}
