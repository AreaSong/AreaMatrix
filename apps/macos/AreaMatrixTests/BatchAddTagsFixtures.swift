@testable import AreaMatrix

extension FileEntrySnapshot {
    static func batchAddTagsRouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.hashSha256 = "batchAddTags-route-\(id)"
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func batchAddTagsTagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "无法批量添加标签",
            suggestedAction: "请保留待添加标签并重试。",
            rawContext: "batch-add-tags batch-add-tags-core batch_add_tags"
        )
    }
}

extension TagSetSnapshot {
    static func batchAddTagsTagCatalogFixture(fileID: Int64) -> TagSetSnapshot {
        let urgent = TagRecordSnapshot.batchAddTagsTag(value: "urgent", fileCount: 3)
        let client = TagRecordSnapshot.batchAddTagsTag(value: "clienta", fileCount: 1)
        return TagSetSnapshot(
            fileID: fileID,
            fileTags: [],
            availableTags: [urgent, client, .batchAddTagsTag(value: "blocked", fileCount: 0, disabled: true)],
            recentTags: [urgent, client],
            updatedAt: 1_700_000_000
        )
    }
}

private extension TagRecordSnapshot {
    static func batchAddTagsTag(value: String, fileCount: Int64, disabled: Bool = false) -> TagRecordSnapshot {
        TagRecordSnapshot(
            value: value,
            label: value,
            fileCount: fileCount,
            selected: false,
            disabled: disabled,
            updatedAt: 1_700_000_000
        )
    }
}

extension BatchMutationReportSnapshot {
    static func batchAddTagsFixture() -> BatchMutationReportSnapshot {
        BatchMutationReportSnapshot(
            requestedFileCount: 2,
            requestedTagCount: 2,
            addedCount: 3,
            skippedCount: 1,
            failedCount: 0,
            itemResults: [
                BatchMutationItemResultSnapshot(fileID: 31, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 31, tag: "clienta", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 32, tag: "urgent", status: .added, error: nil),
                BatchMutationItemResultSnapshot(fileID: 32, tag: "clienta", status: .alreadyHadTag, error: nil)
            ],
            undoToken: "undo-batch-tags"
        )
    }
}
