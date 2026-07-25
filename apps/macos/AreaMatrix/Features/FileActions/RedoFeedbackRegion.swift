import SwiftUI

struct RedoFeedbackRegion: View {
    let state: RedoActionState
    let sourceUndoAction: UndoActionRecordSnapshot?
    let onRedo: (RedoActionRecordSnapshot) -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            Label(L10n.string("Checking redo..."), systemImage: "arrow.uturn.forward.circle")
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-checking")
        case let .available(action):
            redoSummary(action, status: L10n.string("Available"))
            Button(L10n.string("Redo")) { onRedo(action) }
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-action")
        case let .disabled(action, reason):
            redoSummary(action, status: reason)
            Button(L10n.string("Redo")) {}
                .disabled(true)
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-action-disabled")
        case let .unavailable(reason):
            Label(reason, systemImage: "arrow.uturn.forward.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-unavailable")
        case let .redoing(action):
            redoSummary(action, status: L10n.string("Redoing..."))
            Button(L10n.string("Redoing...")) {}
                .disabled(true)
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-action-busy")
        case let .redone(result):
            Label(result.summary, systemImage: "checkmark.circle")
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-completed")
        case let .failed(mapping, action):
            VStack(alignment: .leading, spacing: 3) {
                Label(L10n.string("Could not redo action"), systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                    .foregroundStyle(.secondary)
                if let action {
                    Text(L10n.format("file-actions.redo.row-retained", action.summary))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-failed")
        }
    }

    private func redoSummary(_ action: RedoActionRecordSnapshot, status: String) -> some View {
        let source = RedoUndoSourcePresentation(redoAction: action, undoActions: sourceUndoAction.map { [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 3) {
            Label(action.summary, systemImage: "arrow.uturn.forward.circle")
            Text("\(status) · \(action.affectedCount) affected · \(source.sourceText)")
                .foregroundStyle(.secondary)
        }
    }
}
