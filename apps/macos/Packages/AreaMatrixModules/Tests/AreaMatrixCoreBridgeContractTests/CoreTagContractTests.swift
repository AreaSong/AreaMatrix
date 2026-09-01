@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreTagContractTests: XCTestCase {
    func testTagRecordHasStableIdentityAndDisplayName() {
        let record = TagRecordSnapshot(
            value: "project-x",
            label: "Project X",
            fileCount: 4,
            selected: true,
            disabled: false,
            updatedAt: 10
        )

        XCTAssertEqual(record.id, "project-x")
        XCTAssertEqual(record.displayName, "Project X")
        XCTAssertEqual(record.fileCount, 4)
    }

    func testTagSetAndMutationReportsRemainValueOnlyContracts() {
        let tag = TagRecordSnapshot(
            value: "inbox",
            label: "",
            fileCount: 1,
            selected: false,
            disabled: false,
            updatedAt: 20
        )
        let tagSet = TagSetSnapshot(
            fileID: 7,
            fileTags: [tag],
            availableTags: [tag],
            recentTags: [],
            updatedAt: 20
        )
        let item = BatchMutationItemResultSnapshot(
            fileID: 7,
            tag: "inbox",
            status: .added,
            error: nil
        )
        let report = BatchMutationReportSnapshot(
            requestedFileCount: 1,
            requestedTagCount: 1,
            addedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [item],
            undoToken: "undo-1"
        )

        XCTAssertEqual(tagSet.fileTags.first?.value, "inbox")
        XCTAssertEqual(report.itemResults.first?.id, "7:inbox:added")
        XCTAssertEqual(report.undoToken, "undo-1")
    }

    func testAITagSuggestionRequestCapturesPrivacyReferenceWithoutGeneratedBindings() {
        let request = AITagSuggestionRequestSnapshot(
            fileID: 12,
            candidateTags: ["work"],
            privacyPolicyRef: "local-only"
        )

        XCTAssertEqual(request.fileID, 12)
        XCTAssertEqual(request.candidateTags, ["work"])
        XCTAssertEqual(request.privacyPolicyRef, "local-only")
    }

    func testTagSuggestionContractsPreserveSelectionAndApplySafety() {
        let suggestion = TagSuggestionSnapshot(
            suggestionID: "tag-1",
            slug: "project-x",
            displayName: "Project X",
            reason: "Matches the source folder",
            source: .sourceFolder,
            matchStrength: .strong,
            alreadyExists: false,
            needsCreate: true,
            status: .newTag,
            selectedByDefault: true,
            disabledReason: nil
        )
        let request = TagSuggestionRequestSnapshot(
            fileID: 9,
            context: TagSuggestionContextSnapshot(sourceFolder: "Project X", sourceKeywords: ["project"]),
            limit: 5
        )
        let item = ApplyTagSuggestionItemSnapshot(
            suggestionID: suggestion.id,
            slug: suggestion.slug,
            displayName: suggestion.displayName
        )

        XCTAssertTrue(suggestion.canApply)
        XCTAssertEqual(request.context?.sourceKeywords, ["project"])
        XCTAssertEqual(ApplyTagSuggestionsRequestSnapshot(fileID: 9, suggestions: [item]).suggestions.count, 1)
    }

    func testTagCapabilityProtocolsRemainGeneratedBindingFree() {
        actor Store: CoreTagCRUD, CoreAITagSuggestionManaging {
            func listTags(repoPath _: String, fileID _: Int64) async throws -> TagSetSnapshot {
                fatalError()
            }

            func addTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
                fatalError()
            }

            func removeTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
                fatalError()
            }

            func batchAddTags(
                repoPath _: String,
                fileIDs _: [Int64],
                tags _: [String]
            ) async throws -> BatchMutationReportSnapshot {
                fatalError()
            }

            func suggestTagsForFile(
                repoPath _: String,
                request _: TagSuggestionRequestSnapshot
            ) async throws -> TagSuggestionReportSnapshot {
                fatalError()
            }

            func applyTagSuggestions(
                repoPath _: String,
                request _: ApplyTagSuggestionsRequestSnapshot
            ) async throws -> TagSuggestionApplyReportSnapshot {
                fatalError()
            }

            func suggestTagsWithAI(
                repoPath _: String,
                request _: AITagSuggestionRequestSnapshot
            ) async throws -> AITagSuggestionReportSnapshot {
                fatalError()
            }

            func applyAITagSuggestions(
                repoPath _: String,
                request _: ApplyAITagSuggestionsRequestSnapshot
            ) async throws -> AITagSuggestionApplyReportSnapshot {
                fatalError()
            }
        }

        let _: any CoreTagCRUD = Store()
        let _: any CoreAITagSuggestionManaging = Store()
    }
}
