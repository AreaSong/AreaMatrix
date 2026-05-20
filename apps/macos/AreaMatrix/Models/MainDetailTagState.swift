import Foundation

enum DetailTagEditorOperation: Equatable {
    case load
    case add(String)
    case remove(String)

    var tag: String? {
        switch self {
        case .load:
            nil
        case let .add(tag), let .remove(tag):
            tag
        }
    }
}

enum DetailTagUndoAction: String, Equatable {
    case removeAddedTag
    case restoreRemovedTag
}

struct DetailTagUndoToast: Equatable, Identifiable {
    let fileID: Int64
    let tagValue: String
    let tagLabel: String
    let action: DetailTagUndoAction

    var id: String {
        "\(fileID):\(action.rawValue):\(tagValue)"
    }

    var message: String {
        switch action {
        case .removeAddedTag:
            "Added tag \"\(displayName)\"."
        case .restoreRemovedTag:
            "Removed tag \"\(displayName)\"."
        }
    }

    var undoOperation: DetailTagEditorOperation {
        switch action {
        case .removeAddedTag:
            .remove(tagValue)
        case .restoreRemovedTag:
            .add(tagValue)
        }
    }

    func belongs(to fileID: Int64) -> Bool {
        self.fileID == fileID
    }

    private var displayName: String {
        tagLabel.isEmpty ? tagValue : tagLabel
    }
}

extension DetailTagUndoToast {
    static func addedTag(
        fileID: Int64,
        previous: TagSetSnapshot?,
        current: TagSetSnapshot
    ) -> DetailTagUndoToast? {
        guard let tag = current.fileTags.first(where: { tag in
            previous?.containsFileTag(value: tag.value) != true
        }) else { return nil }

        return DetailTagUndoToast(
            fileID: fileID,
            tagValue: tag.value,
            tagLabel: tag.displayName,
            action: .removeAddedTag
        )
    }

    static func removedTag(
        fileID: Int64,
        previous: TagSetSnapshot?,
        current: TagSetSnapshot
    ) -> DetailTagUndoToast? {
        guard let tag = previous?.fileTags.first(where: { tag in
            !current.containsFileTag(value: tag.value)
        }) else { return nil }

        return DetailTagUndoToast(
            fileID: fileID,
            tagValue: tag.value,
            tagLabel: tag.displayName,
            action: .restoreRemovedTag
        )
    }
}

enum DetailTagEditorState: Equatable {
    case notLoaded
    case loading(fileID: Int64, previous: TagSetSnapshot?)
    case loaded(fileID: Int64, TagSetSnapshot)
    case failed(fileID: Int64, operation: DetailTagEditorOperation, CoreErrorMappingSnapshot, previous: TagSetSnapshot?)

    var tagSet: TagSetSnapshot? {
        switch self {
        case let .loaded(_, tagSet), let .loading(_, tagSet?),
             let .failed(_, _, _, tagSet?):
            tagSet
        case .notLoaded, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: (operation: DetailTagEditorOperation, mapping: CoreErrorMappingSnapshot)? {
        guard case let .failed(_, operation, mapping, _) = self else { return nil }
        return (operation, mapping)
    }
}

extension TagSetSnapshot {
    func containsFileTag(value: String) -> Bool {
        fileTags.contains { $0.value.caseInsensitiveCompare(value) == .orderedSame }
    }
}
