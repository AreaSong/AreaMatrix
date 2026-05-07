import Foundation

enum DetailPaneTab: String, CaseIterable, Identifiable, Sendable {
    case meta
    case log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meta:
            return "Meta"
        case .log:
            return "Log"
        }
    }
}

enum MainFileSelectionState: Equatable, Sendable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    var singleFileID: Int64? {
        if case .single(let id) = self { return id }
        return nil
    }

    var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }
}

enum MainFileActionDestination: Equatable, Sendable {
    case rename(fileID: Int64)
    case changeCategory(fileID: Int64)
    case delete(fileID: Int64)

    var pageID: String {
        switch self {
        case .rename:
            return "S1-33"
        case .changeCategory:
            return "S1-35"
        case .delete:
            return "S1-34"
        }
    }

    var pageTitle: String {
        switch self {
        case .rename:
            return "Rename File"
        case .changeCategory:
            return "Change Category"
        case .delete:
            return "Move File to Trash?"
        }
    }

    var fileID: Int64 {
        switch self {
        case .rename(let fileID), .changeCategory(let fileID), .delete(let fileID):
            return fileID
        }
    }
}

extension MainFileActionDestination: Identifiable {
    var id: String {
        "\(pageID)-\(fileID)"
    }
}

enum MainListStatusBanner: Equatable, Sendable {
    case renamedPreservedSelection(fileID: Int64)
    case removedSelectedFile(fileID: Int64)

    var message: String {
        switch self {
        case .renamedPreservedSelection:
            return "External rename detected. The same file remains selected."
        case .removedSelectedFile:
            return "Selected file is missing or was removed outside AreaMatrix."
        }
    }
}

enum MainDetailTabRequest: Equatable, Sendable {
    case automatic(DetailPaneTab)
}

enum MainFileWriteActionDisabledReason: String, Equatable, Sendable {
    case repoReadOnly = "Repository is read-only"
    case listLoading = "Current list is loading"
    case importLocked = "This file is locked by an import"
}

enum MainFileActionCategoryOptions {
    static func availableCategories(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> [String] {
        let categories = categoryRows.compactMap(\.categoryForFileList)
        let current = file.map { [$0.category] } ?? []
        return Array(Set(categories + current)).sorted()
    }

    static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let categories = availableCategories(file: nil, categoryRows: categoryRows)
        return categories.first { $0 != file?.category } ?? file?.category ?? ""
    }
}

enum MainListDiagnosticsState: Equatable, Sendable {
    case idle
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum MainDetailLogState: Equatable, Sendable {
    case notLoaded
    case loading(fileID: Int64)
    case loaded(fileID: Int64, entries: [ChangeLogEntrySnapshot])
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum MainDetailLogDiagnosticsState: Equatable, Sendable {
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
