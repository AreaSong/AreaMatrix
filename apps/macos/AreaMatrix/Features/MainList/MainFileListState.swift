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
