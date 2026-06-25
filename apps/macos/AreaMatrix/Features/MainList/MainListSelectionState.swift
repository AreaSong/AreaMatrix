import Foundation

enum MainFileSelectionState: Equatable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    var singleFileID: Int64? {
        if case let .single(id) = self { return id }
        return nil
    }

    var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }

    var multipleFileIDs: Set<Int64> {
        if case let .multiple(ids) = self { return ids }
        return []
    }
}
