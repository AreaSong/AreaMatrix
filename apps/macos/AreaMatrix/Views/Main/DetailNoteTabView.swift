import SwiftUI

struct DetailNoteTabView: View {
    @ObservedObject var model: DetailNoteModel
    let file: FileEntrySnapshot
    let writeBlock: MainDetailNoteWriteBlock?
    let onOpenNoteFile: (String) -> Void

    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            stateContent
        }
        .task(id: file.id) {
            await model.load(file: file, writeBlock: writeBlock)
        }
        .onChange(of: writeBlock) { _, block in
            model.updateWriteBlock(block)
        }
        .onChange(of: model.editorFocusRequest) { _, isRequested in
            guard isRequested else { return }
            isEditorFocused = true
            model.consumeEditorFocusRequest()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Note")
                .font(.headline)
            Spacer()
            if let saveStatus = model.state.saveStatus {
                NoteSaveStatusView(status: saveStatus)
            }
            Button {
                if let notePath = model.noteSidecarRelativePath {
                    onOpenNoteFile(notePath)
                }
            } label: {
                Label("Open note file", systemImage: "doc.text")
            }
            .disabled(!model.canOpenNoteFile)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .notLoaded, .loading:
            noteLoadingView
        case .empty:
            emptyState
        case .editing:
            editorState
        case .failed(_, let error, _):
            noteLoadError(error)
        }
    }

    private var noteLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading note...")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有笔记")
                .font(.headline)
            Text("为这个文件添加上下文、处理状态或关联信息。")
                .foregroundStyle(.secondary)
            if let message = model.state.writeBlock?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Create Note", action: model.createNote)
                .disabled(model.state.writeBlock != nil)
        }
        .accessibilityElement(children: .contain)
    }

    private var editorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.state.writeBlock?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(
                get: { model.noteText },
                set: { model.updateDraft($0) }
            ))
            .font(.body)
            .frame(minHeight: 180)
            .accessibilityLabel("Companion note")
            .disabled(model.state.writeBlock != nil)
            .focused($isEditorFocused)
            if let error = model.state.saveStatus?.failedError {
                saveErrorView(error)
            }
            if !model.canOpenNoteFile {
                Text("Save the note before opening the sidecar file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func noteLoadError(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法加载笔记", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await model.retryLoad() }
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .contain)
    }

    private func saveErrorView(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法保存笔记", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await model.retrySave() }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

private struct NoteSaveStatusView: View {
    let status: MainDetailNoteSaveStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Note save status \(status.title)")
    }

    private var color: Color {
        switch status {
        case .saved:
            return .secondary
        case .saving:
            return .blue
        case .unsaved, .failed:
            return .orange
        }
    }
}
