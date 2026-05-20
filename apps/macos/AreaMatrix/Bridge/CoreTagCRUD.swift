import Foundation

protocol CoreTagCRUD: Sendable {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot
    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
}

struct TagRecordSnapshot: Equatable, Identifiable {
    var value: String
    var label: String
    var fileCount: Int64
    var selected: Bool
    var disabled: Bool
    var updatedAt: Int64

    var id: String { value }

    var displayName: String {
        label.isEmpty ? value : label
    }
}

struct TagSetSnapshot: Equatable {
    var fileID: Int64
    var fileTags: [TagRecordSnapshot]
    var availableTags: [TagRecordSnapshot]
    var recentTags: [TagRecordSnapshot]
    var updatedAt: Int64
}

extension CoreBridge: CoreTagCRUD {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.listTags(repoPath: repoPath, fileId: fileID))
        }.value
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.addTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.removeTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }
}

private extension TagSetSnapshot {
    init(coreTagSet: TagSet) {
        fileID = coreTagSet.fileId
        fileTags = coreTagSet.fileTags.map(TagRecordSnapshot.init(coreRecord:))
        availableTags = coreTagSet.availableTags.map(TagRecordSnapshot.init(coreRecord:))
        recentTags = coreTagSet.recentTags.map(TagRecordSnapshot.init(coreRecord:))
        updatedAt = coreTagSet.updatedAt
    }
}

private extension TagRecordSnapshot {
    init(coreRecord: TagRecord) {
        value = coreRecord.value
        label = coreRecord.label
        fileCount = coreRecord.fileCount
        selected = coreRecord.selected
        disabled = coreRecord.disabled
        updatedAt = coreRecord.updatedAt
    }
}
