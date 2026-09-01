import Foundation

public enum MainFileSelectionState: Equatable, Sendable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    public var singleFileID: Int64? {
        if case let .single(id) = self { return id }
        return nil
    }

    public var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }

    public var multipleFileIDs: Set<Int64> {
        if case let .multiple(ids) = self { return ids }
        return []
    }
}

public enum SearchDateFilterPreset: Equatable, Sendable {
    case any
    case last7Days
    case last30Days
    case thisYear
}

public enum MainSearchEntryContext: Equatable, Sendable {
    case toolbar
    case commandFind
    case smartList(id: Int64, name: String)
    case commandPalette
    case sidebar(String)
}

public enum MainSearchExitContext: Equatable, Sendable {
    case toolbar
    case smartList(id: Int64, name: String)
    case sidebar(String)
    case list
}

public enum MainDetailNoteWriteBlock: Equatable, Sendable {
    case repoReadOnly
    case fileMissing
    case importLocked
    case listLoading
}

public enum SemanticSearchResultGroup: Equatable, Sendable {
    case semantic
    case normal
}
