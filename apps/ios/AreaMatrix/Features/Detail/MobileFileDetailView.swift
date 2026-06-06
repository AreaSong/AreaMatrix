import SwiftUI

struct MobileFileDetailView: View {
    @StateObject private var model: MobileFileDetailViewModel
    private let onOpenMissingRecovery: (Int64) -> Void

    init(
        repoPath: String,
        fileID: Int64,
        bridge: any MobileFileDetailCoreBridge,
        onOpenMissingRecovery: @escaping (Int64) -> Void = { _ in }
    ) {
        _model = StateObject(wrappedValue: MobileFileDetailViewModel(
            repoPath: repoPath,
            fileID: fileID,
            bridge: bridge
        ))
        self.onOpenMissingRecovery = onOpenMissingRecovery
    }

    var body: some View {
        List {
            statusSection
            metadataContent
        }
        .mobileFileDetailListStyle()
        .navigationTitle(model.navigationTitle)
        .toolbar {
            Button {
                Task { await model.reloadMetadata() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh file detail")
        }
        .task {
            await model.loadMetadataIfNeeded()
        }
        .onChange(of: model.selectedSegment) { _, _ in
            Task { await model.loadSelectedSegmentIfNeeded() }
        }
        .onChange(of: model.missingRecoveryRouteFileID) { _, fileID in
            guard let fileID else { return }
            onOpenMissingRecovery(fileID)
            model.clearMissingRecoveryRoute()
        }
    }

    private var statusSection: some View {
        Section {
            Label(model.statusText, systemImage: statusIcon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(statusColor)
                .accessibilityIdentifier("S4-IOS-05-C4-07-status")
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        switch model.metadataState {
        case .notLoaded, .loading:
            Section {
                ProgressView("Loading file detail...")
            }
        case let .failed(error):
            Section {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Retry") {
                    Task { await model.reloadMetadata() }
                }
            }
        case let .loaded(file):
            FilePreviewHeader(file: file) {
                model.requestMissingRecoveryRoute()
            }
            Section {
                Picker("Detail section", selection: $model.selectedSegment) {
                    ForEach(MobileFileDetailSegment.allCases) { segment in
                        Text(segment.label).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("S4-IOS-05-C4-07-segments")
            }
            selectedSection(file: file)
        }
    }

    @ViewBuilder
    private func selectedSection(file: MobileFileDetailMetadata) -> some View {
        switch model.selectedSegment {
        case .meta:
            MobileMetadataSection(file: file)
        case .log:
            MobileChangeLogSection(state: model.changeLogState) {
                Task { await model.reloadChangeLog() }
            }
        case .note:
            MobileNoteSection(state: model.noteState) {
                Task { await model.reloadNote() }
            }
        }
    }

    private var statusIcon: String {
        switch model.metadataState {
        case .failed:
            "exclamationmark.triangle"
        case .loading:
            "arrow.triangle.2.circlepath"
        case let .loaded(file) where file.availability == .missing:
            "questionmark.folder"
        default:
            "doc.text"
        }
    }

    private var statusColor: Color {
        switch model.metadataState {
        case .failed:
            .orange
        case let .loaded(file) where file.availability == .missing:
            .orange
        default:
            .secondary
        }
    }
}

private struct FilePreviewHeader: View {
    let file: MobileFileDetailMetadata
    let onRecoverMissing: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: file.availability == .missing ? "questionmark.folder" : "doc.text")
                        .font(.title2)
                        .foregroundStyle(file.availability == .missing ? .orange : .secondary)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(file.currentName)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text(file.categoryPath)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(file.availability.statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(file.availability == .missing ? .orange : .secondary)
                            .accessibilityLabel("Status \(file.availability.statusText)")
                    }
                }
                if file.availability == .missing {
                    Button {
                        onRecoverMissing()
                    } label: {
                        Label("Recover Missing File", systemImage: "arrow.uturn.backward.circle")
                    }
                    .accessibilityIdentifier("S4-IOS-05-C4-07-missing-recovery")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct MobileMetadataSection: View {
    let file: MobileFileDetailMetadata

    var body: some View {
        Section("Meta") {
            DetailValueRow(label: "Relative path", value: file.path)
            DetailValueRow(label: "Original source", value: file.sourceText)
            DetailValueRow(label: "Size", value: file.sizeText)
            DetailValueRow(label: "Modified", value: dateText(file.updatedAt))
            DetailValueRow(label: "Hash", value: file.hashSha256, monospaced: true)
            DetailValueRow(label: "Imported at", value: dateText(file.importedAt))
        }
        .accessibilityIdentifier("S4-IOS-05-C4-07-meta")
    }
}

private struct MobileChangeLogSection: View {
    let state: MobileFileChangeLogState
    let onRetry: () -> Void

    var body: some View {
        Section("Log") {
            switch state {
            case .notLoaded, .loading:
                ProgressView("Loading changes...")
            case let .loaded(entries) where entries.isEmpty:
                Label("No changes yet.", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case let .loaded(entries):
                ForEach(entries) { entry in
                    ChangeLogEntryRow(entry: entry)
                }
            case let .failed(error):
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again", action: onRetry)
            }
        }
        .accessibilityIdentifier("S4-IOS-05-C4-07-log")
    }
}

private struct ChangeLogEntryRow: View {
    let entry: MobileFileChangeLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.actionDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.isWarning ? .orange : .primary)
                Spacer()
                Text(dateText(entry.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.detailSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MobileNoteSection: View {
    let state: MobileFileNoteState
    let onRetry: () -> Void

    var body: some View {
        Section("Note") {
            switch state {
            case .notLoaded, .loading:
                ProgressView("Loading note...")
            case let .loaded(note):
                if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .textSelection(.enabled)
                } else {
                    Text("Add a note for this file.")
                        .foregroundStyle(.secondary)
                }
            case let .failed(error):
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again", action: onRetry)
            }
        }
        .accessibilityIdentifier("S4-IOS-05-C4-07-note")
    }
}

private struct DetailValueRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(monospaced ? .footnote.monospaced() : .footnote)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}

private func dateText(_ timestamp: Int64) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestamp))
        .formatted(date: .abbreviated, time: .shortened)
}

private extension View {
    @ViewBuilder
    func mobileFileDetailListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}
