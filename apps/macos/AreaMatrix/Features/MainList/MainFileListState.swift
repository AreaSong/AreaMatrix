import Foundation

enum DetailPaneTab: String, CaseIterable, Identifiable {
    case meta
    case summary
    case log
    case note

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .meta:
            "Meta"
        case .summary:
            "Summary"
        case .log:
            "Log"
        case .note:
            "Note"
        }
    }
}

enum MainDetailTabRequest: Equatable {
    case automatic(DetailPaneTab)
}

enum MainMissingFileRelinkState: Equatable {
    case idle
    case loading(fileID: Int64)
    case relinking(fileID: Int64)
    case hashMismatch(fileID: Int64, message: String)
    case unavailable(fileID: Int64, message: String)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    func isBusy(for fileID: Int64) -> Bool {
        switch self {
        case let .loading(currentFileID), let .relinking(currentFileID):
            currentFileID == fileID
        case .idle, .hashMismatch, .unavailable, .failed:
            false
        }
    }

    func message(for fileID: Int64) -> String? {
        switch self {
        case let .hashMismatch(currentFileID, message), let .unavailable(currentFileID, message):
            currentFileID == fileID ? message : nil
        case let .failed(currentFileID, mapping):
            currentFileID == fileID ? mapping.userMessage : nil
        case .idle, .loading, .relinking:
            nil
        }
    }
}

extension MainFileDeleteOperation {
    func successBanner(fileID: Int64) -> MainListStatusBanner {
        switch self {
        case .moveToTrash:
            .movedFileToTrash(fileID: fileID)
        case .removeFromIndex:
            .removedFileFromIndex(fileID: fileID)
        }
    }
}

enum MainListDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum MainDetailLogState: Equatable {
    case notLoaded
    case loading(fileID: Int64)
    case loaded(fileID: Int64, entries: [ChangeLogEntrySnapshot])
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var entries: [ChangeLogEntrySnapshot]? {
        guard case let .loaded(_, entries) = self else { return nil }
        return entries
    }
}

enum MainDetailLogDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy(fileID: Int64)
    case collecting(fileID: Int64)
    case collected(fileID: Int64, DiagnosticsSnapshotSnapshot)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}
