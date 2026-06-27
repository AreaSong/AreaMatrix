import SwiftUI

struct BatchTagUndoToastView: View {
    let state: BatchTagUndoState
    let redoState: RedoActionState
    let redoSourceUndoAction: UndoActionRecordSnapshot?
    let actionLogRefreshFailure: CoreErrorMappingSnapshot?
    let onUndo: (UndoActionRecordSnapshot) -> Void
    let onRedo: (RedoActionRecordSnapshot) -> Void
    let onOpenHistory: (UndoToastHistoryRequest.Source) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                toastLabel
                Spacer()
                toastActions
            }
            RedoFeedbackRegion(state: redoState, sourceUndoAction: redoSourceUndoAction, onRedo: onRedo)
        }
        .font(.caption)
        .padding(8)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("undo-toast-undo-action-log-undo-toast")
    }

    @ViewBuilder
    private var toastLabel: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            Label("Loading undo action...", systemImage: "arrow.uturn.backward.circle")
        case let .ready(action):
            undoSummary(action, status: "Undo available")
        case let .disabled(action, reason):
            disabledUndoSummary(action, reason: reason)
        case let .unavailable(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
        case let .undoing(action):
            undoSummary(action, status: "Undoing...")
        case let .undone(result):
            VStack(alignment: .leading, spacing: 3) {
                Label(result.summary, systemImage: "checkmark.circle")
                if let actionLogRefreshFailure {
                    Text(actionLogRefreshFailure.userMessage)
                        .foregroundStyle(.secondary)
                }
            }
        case let .failed(mapping, _):
            VStack(alignment: .leading, spacing: 3) {
                Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var toastActions: some View {
        if case let .ready(action) = state {
            Button("Undo") { onUndo(action) }
                .accessibilityIdentifier("undo-toast-undo-action-log-undo-action")
        } else if case .disabled = state {
            Button("Undo") {}
                .disabled(true)
                .accessibilityIdentifier("undo-toast-undo-action-log-undo-action-disabled")
        }
        if case .failed = state {
            Button("View details") { onOpenHistory(.viewDetails) }
                .help("Open Undo History details for this failed undo.")
                .accessibilityIdentifier("undo-toast-undo-action-log-view-details")
        } else {
            Button("View history") { onOpenHistory(.viewHistory) }
                .help("Open Undo History for this action.")
                .accessibilityIdentifier("undo-toast-undo-action-log-view-history")
        }
        Button("Dismiss", action: onDismiss)
    }

    private func undoSummary(_ action: UndoActionRecordSnapshot, status: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(action.summary, systemImage: "arrow.uturn.backward.circle")
            Text("\(status) · \(action.affectedCount) affected")
                .foregroundStyle(.secondary)
        }
    }

    private func disabledUndoSummary(_ action: UndoActionRecordSnapshot, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(action.summary, systemImage: "exclamationmark.triangle")
            Text(reason)
                .foregroundStyle(.secondary)
        }
    }
}
