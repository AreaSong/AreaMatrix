import Foundation

enum MobileFileDetailSegment: String, CaseIterable, Equatable, Identifiable, Sendable {
    case meta
    case log
    case note

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .meta:
            "Meta"
        case .log:
            "Log"
        case .note:
            "Note"
        }
    }
}

enum MobileFileMetadataState: Equatable {
    case notLoaded
    case loading
    case loaded(MobileFileDetailMetadata)
    case failed(MobileFileDetailError)

    var file: MobileFileDetailMetadata? {
        guard case let .loaded(file) = self else { return nil }
        return file
    }

    var error: MobileFileDetailError? {
        guard case let .failed(error) = self else { return nil }
        return error
    }
}

enum MobileFileChangeLogState: Equatable {
    case notLoaded
    case loading
    case loaded([MobileFileChangeLogEntry])
    case failed(MobileFileDetailError)
}

enum MobileFileNoteState: Equatable {
    case notLoaded
    case loading
    case loaded(String?)
    case failed(MobileFileDetailError)
}

@MainActor
final class MobileFileDetailViewModel: ObservableObject {
    @Published private(set) var metadataState: MobileFileMetadataState = .notLoaded
    @Published private(set) var changeLogState: MobileFileChangeLogState = .notLoaded
    @Published private(set) var noteState: MobileFileNoteState = .notLoaded
    @Published private(set) var missingRecoveryRouteFileID: Int64?
    @Published var selectedSegment: MobileFileDetailSegment = .meta

    let repoPath: String
    let fileID: Int64

    private let bridge: any MobileFileDetailCoreBridge

    init(repoPath: String, fileID: Int64, bridge: any MobileFileDetailCoreBridge) {
        self.repoPath = repoPath
        self.fileID = fileID
        self.bridge = bridge
    }

    var navigationTitle: String {
        metadataState.file?.currentName ?? "File Detail"
    }

    var statusText: String {
        if metadataState == .loading {
            return "Loading file detail..."
        }
        if let error = metadataState.error {
            return error.message
        }
        if let file = metadataState.file {
            return file.availability.statusText
        }
        return "File detail"
    }

    var canRequestMissingRecovery: Bool {
        metadataState.file?.availability == .missing
    }

    func loadMetadataIfNeeded() async {
        guard metadataState == .notLoaded else { return }
        await reloadMetadata()
    }

    func reloadMetadata() async {
        metadataState = .loading
        missingRecoveryRouteFileID = nil
        do {
            metadataState = .loaded(try await bridge.getFile(repoPath: repoPath, fileID: fileID))
        } catch {
            metadataState = .failed(MobileFileDetailError.map(error))
        }
    }

    func loadSelectedSegmentIfNeeded() async {
        switch selectedSegment {
        case .meta:
            await loadMetadataIfNeeded()
        case .log:
            await loadChangeLogIfNeeded()
        case .note:
            await loadNoteIfNeeded()
        }
    }

    func loadChangeLogIfNeeded() async {
        guard changeLogState == .notLoaded else { return }
        await reloadChangeLog()
    }

    func reloadChangeLog() async {
        changeLogState = .loading
        let filter = MobileFileDetailChangeFilter.detail(fileID: fileID)
        do {
            changeLogState = .loaded(try await bridge.listChanges(repoPath: repoPath, filter: filter))
        } catch {
            changeLogState = .failed(MobileFileDetailError.map(error))
        }
    }

    func loadNoteIfNeeded() async {
        guard noteState == .notLoaded else { return }
        await reloadNote()
    }

    func reloadNote() async {
        noteState = .loading
        do {
            noteState = .loaded(try await bridge.readNote(repoPath: repoPath, fileID: fileID))
        } catch {
            noteState = .failed(MobileFileDetailError.map(error))
        }
    }

    func requestMissingRecoveryRoute() {
        guard canRequestMissingRecovery else { return }
        missingRecoveryRouteFileID = metadataState.file?.id
    }

    func clearMissingRecoveryRoute() {
        missingRecoveryRouteFileID = nil
    }
}
