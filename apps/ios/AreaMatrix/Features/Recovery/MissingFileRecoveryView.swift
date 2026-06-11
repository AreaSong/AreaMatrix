import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MissingFileRecoveryCopy {
    static let title = "File is missing"
    static let locate = "Locate File"
    static let tryAgain = "Try Again"
    static let decideLater = "Decide Later"
    static let removeRecord = "Remove Record..."
    static let confirmTitle = "Remove this record?"
    static let confirmText = "This removes the AreaMatrix record only. It will not delete any user file from disk."
    static let confirmCheckbox = "I understand this only removes the record."
    static let remove = "Remove Record"
    static let relink = "Relink File"
    static let checking = "Checking file..."
}

enum MissingFileRecoveryAccessibilityID {
    static let sheet = "S4-X-06-C4-18-ios-sheet"
    static let locate = "S4-X-06-C4-18-ios-locate"
    static let relink = "S4-X-06-C4-18-ios-relink"
    static let tryAgain = "S4-X-06-C4-18-ios-try-again"
    static let removeRecord = "S4-X-06-C4-18-ios-remove-record"
    static let confirmRemove = "S4-X-06-C4-18-ios-confirm-remove"
}

struct MissingFileRecoveryRoute: Identifiable, Equatable {
    var repoPath: String
    var fileID: Int64

    var id: String {
        "\(repoPath)#\(fileID)"
    }
}

enum MissingFileRecoveryLoadState: Equatable {
    case idle
    case loading
    case loaded(MissingFileRecoveryState)
    case failed(MissingFileRecoveryError)
}

@MainActor
final class MissingFileRecoveryViewModel: ObservableObject {
    @Published private(set) var loadState: MissingFileRecoveryLoadState = .idle
    @Published private(set) var isWorking = false
    @Published private(set) var selectedRelinkURL: URL?
    @Published var removeRecordConfirmed = false
    @Published private(set) var report: MissingFileRecoveryReport?
    @Published private(set) var actionError: MissingFileRecoveryError?

    private let repoPath: String
    private let fileID: Int64
    private let bridge: any MissingFileRecoveryCoreBridge
    private let fileAccess: any MissingFileRecoveryFileAccessing

    init(
        repoPath: String,
        fileID: Int64,
        bridge: any MissingFileRecoveryCoreBridge,
        fileAccess: any MissingFileRecoveryFileAccessing =
            MissingFileRecoverySecurityScopedFileAccessService()
    ) {
        self.repoPath = repoPath
        self.fileID = fileID
        self.bridge = bridge
        self.fileAccess = fileAccess
    }

    var state: MissingFileRecoveryState? {
        guard case let .loaded(state) = loadState else { return nil }
        return state
    }

    var selectedRelinkPath: String {
        selectedRelinkURL?.path ?? ""
    }

    var canRelink: Bool {
        state?.canLocate == true && selectedRelinkURL != nil && !isWorking
    }

    var canTryAgain: Bool {
        state?.canTryAgain == true && !isWorking
    }

    var canRemoveRecord: Bool {
        guard let state, state.canRemoveRecord, !isWorking else { return false }
        return !state.removeRecordRequiresConfirmation || removeRecordConfirmed
    }

    func load() async {
        loadState = .loading
        actionError = nil
        report = nil
        do {
            loadState = .loaded(try await bridge.getMissingFileState(repoPath: repoPath, fileID: fileID))
        } catch {
            loadState = .failed(MissingFileRecoveryError.map(error))
        }
    }

    func tryAgain() async {
        guard canTryAgain else { return }
        await load()
    }

    func selectRelinkFile(_ url: URL) {
        guard state?.canLocate == true, !isWorking else { return }
        selectedRelinkURL = url.standardizedFileURL
        actionError = nil
        report = nil
    }

    func handleLocateFilePickerFailure(_ error: Error) {
        guard !Self.isUserCancellation(error) else { return }
        actionError = MissingFileRecoveryError.map(error)
    }

    func relinkSelectedFile() async {
        guard canRelink, let selectedRelinkURL else { return }
        await runAction {
            let scopedAccess = try fileAccess.beginAccessing(selectedRelinkURL)
            defer { scopedAccess.stop() }
            return try await bridge.relinkMissingFile(
                repoPath: repoPath,
                request: MissingFileRelinkRequest(
                    fileID: fileID,
                    newPath: selectedRelinkURL.path,
                    confirmed: true
                )
            )
        }
    }

    func removeRecord() async {
        guard canRemoveRecord else { return }
        await runAction {
            try await bridge.removeMissingFileRecord(
                repoPath: repoPath,
                request: MissingFileRemoveRecordRequest(fileID: fileID, confirmed: true)
            )
        }
    }

    private func runAction(_ action: () async throws -> MissingFileRecoveryReport) async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            report = try await action()
            if report?.status == .hashMismatch {
                actionError = .unavailable(report?.displayMessage ?? "")
            }
        } catch {
            actionError = MissingFileRecoveryError.map(error)
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

struct MissingFileRecoveryView: View {
    @ObservedObject var model: MissingFileRecoveryViewModel
    let onDecideLater: () -> Void
    @State private var isShowingLocatePicker = false

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle(MissingFileRecoveryCopy.title)
            .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.sheet)
            .task {
                if case .idle = model.loadState {
                    await model.load()
                }
            }
            .fileImporter(
                isPresented: $isShowingLocatePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: handleLocateFilePickerResult
            )
        }
    }
}

private extension MissingFileRecoveryView {
    @ViewBuilder
    var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView(MissingFileRecoveryCopy.checking)
        case let .failed(error):
            errorSection(error)
        case let .loaded(state):
            summarySection(state)
            relinkSection(state)
            removeRecordSection(state)
            if let report = model.report {
                reportSection(report)
            }
            if let actionError = model.actionError {
                errorSection(actionError)
            }
        }
    }

    func summarySection(_ state: MissingFileRecoveryState) -> some View {
        Section {
            LabeledContent("File", value: state.fileText)
            LabeledContent("Last known location", value: state.lastKnownLocationText)
            LabeledContent("Last seen", value: state.lastSeenText)
            LabeledContent("Reason", value: state.reason.displayText)
        }
        .accessibilityElement(children: .contain)
    }

    func relinkSection(_ state: MissingFileRecoveryState) -> some View {
        Section("Recovery") {
            Text(state.hashRequirementText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(MissingFileRecoveryCopy.locate) {
                isShowingLocatePicker = true
            }
            .disabled(!state.canLocate || model.isWorking)
            .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.locate)
            if !model.selectedRelinkPath.isEmpty {
                LabeledContent("Selected file", value: model.selectedRelinkPath)
            }
            Button(MissingFileRecoveryCopy.relink) {
                Task { await model.relinkSelectedFile() }
            }
            .disabled(!model.canRelink)
            .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.relink)
            Button(MissingFileRecoveryCopy.tryAgain) {
                Task { await model.tryAgain() }
            }
            .disabled(!model.canTryAgain)
            .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.tryAgain)
            Button(MissingFileRecoveryCopy.decideLater, action: onDecideLater)
        }
    }

    func removeRecordSection(_ state: MissingFileRecoveryState) -> some View {
        Section(MissingFileRecoveryCopy.confirmTitle) {
            Text(MissingFileRecoveryCopy.confirmText)
                .foregroundStyle(.secondary)
            Toggle(MissingFileRecoveryCopy.confirmCheckbox, isOn: $model.removeRecordConfirmed)
                .disabled(!state.removeRecordRequiresConfirmation || model.isWorking)
            Button(role: .destructive) {
                Task { await model.removeRecord() }
            } label: {
                Text(MissingFileRecoveryCopy.remove)
            }
            .disabled(!model.canRemoveRecord)
            .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.confirmRemove)
        }
        .accessibilityIdentifier(MissingFileRecoveryAccessibilityID.removeRecord)
    }

    func reportSection(_ report: MissingFileRecoveryReport) -> some View {
        Section("Result") {
            Text(report.displayMessage)
            if let action = report.changeLogAction {
                LabeledContent("Change log", value: action)
            }
            LabeledContent("Deleted file", value: report.fileDeleted ? "Yes" : "No")
        }
    }

    func errorSection(_ error: MissingFileRecoveryError) -> some View {
        Section {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error.recovery)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func handleLocateFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            model.selectRelinkFile(url)
        case let .failure(error):
            model.handleLocateFilePickerFailure(error)
        }
    }
}
