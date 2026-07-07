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
        return TagSetSnapshot.testFixture(
            fileID: fileID,
            availableTags: [urgent, client, .batchAddTagsTag(value: "blocked", fileCount: 0, disabled: true)],
            recentTags: [urgent, client],
            updatedAt: 1_700_000_000
        )
    }
}

private extension TagRecordSnapshot {
    static func batchAddTagsTag(value: String, fileCount: Int64, disabled: Bool = false) -> TagRecordSnapshot {
        TagRecordSnapshot.testFixture(
            value: value,
            fileCount: fileCount,
            disabled: disabled,
            updatedAt: 1_700_000_000
        )
    }
}

extension BatchMutationItemResultSnapshot {
    static func testFixture(
        fileID: Int64,
        tag: String,
        status: BatchMutationStatusSnapshot = .added,
        error: String? = nil
    ) -> BatchMutationItemResultSnapshot {
        BatchMutationItemResultSnapshot(
            fileID: fileID,
            tag: tag,
            status: status,
            error: error
        )
    }
}

extension BatchMutationReportSnapshot {
    static func testFixture(
        requestedFileCount: Int64,
        requestedTagCount: Int64,
        addedCount: Int64,
        skippedCount: Int64 = 0,
        failedCount: Int64 = 0,
        itemResults: [BatchMutationItemResultSnapshot] = [],
        undoToken: String? = nil
    ) -> BatchMutationReportSnapshot {
        BatchMutationReportSnapshot(
            requestedFileCount: requestedFileCount,
            requestedTagCount: requestedTagCount,
            addedCount: addedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            itemResults: itemResults,
            undoToken: undoToken
        )
    }

    static func batchAddTagsFixture() -> BatchMutationReportSnapshot {
        testFixture(
            requestedFileCount: 2,
            requestedTagCount: 2,
            addedCount: 3,
            skippedCount: 1,
            failedCount: 0,
            itemResults: [
                .testFixture(fileID: 31, tag: "urgent"),
                .testFixture(fileID: 31, tag: "clienta"),
                .testFixture(fileID: 32, tag: "urgent"),
                .testFixture(fileID: 32, tag: "clienta", status: .alreadyHadTag)
            ],
            undoToken: "undo-batch-tags"
        )
    }
}
