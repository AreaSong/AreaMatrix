@testable import AreaMatrix
import XCTest

final class AITagBatchPageFeatureTests: XCTestCase {
    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreBatchReviewConfirmsBeforeApplyingTags() async {
        let files = [
            FileEntrySnapshot.detailMetaFixture(id: 707, currentName: "invoice-a.pdf"),
            FileEntrySnapshot.detailMetaFixture(id: 708, currentName: "invoice-b.pdf")
        ]
        let bridge = AITagSuggestionBatchAITagBridge(reports: Dictionary(uniqueKeysWithValues: files.map {
            ($0.id, aiTagSuggestionAITagReport(fileID: $0.id, suggestions: [
                aiTagSuggestionAITagSuggestion(id: "ai-tag-finance-\($0.id)", slug: "finance", confidence: 0.91)
            ]))
        }))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: files),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.tagSuggestionsApplied()]),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles(Set(files.map(\.id)))
        await model.loadBatchAITagSuggestions(files: files)
        await bridge.assertSuggestFileIDs([707, 708])
        await bridge.assertNoApplyRequests()
        model.confirmBatchAITagSuggestions()
        await bridge.assertNoApplyRequests()
        await model.applyBatchAITagSuggestions()

        await bridge.assertApplyFileIDs([707, 708], confirmed: true)
        XCTAssertEqual(model.aiTagBatchSuggestionState.review?.appliedFileCount, 2)
        XCTAssertEqual(model.aiTagBatchSuggestionState.review?.selectedTagCount, 0)
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreBatchPartialFailureKeepsFailedSuggestionsPending() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 717, currentName: "invoice-ok.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 718, currentName: "invoice-fail.pdf")
        let bridge = AITagSuggestionBatchAITagBridge(
            reports: [
                first.id: aiTagSuggestionAITagReport(fileID: first.id, suggestions: [
                    aiTagSuggestionAITagSuggestion(id: "ai-tag-ok", slug: "finance", confidence: 0.93)
                ]),
                second.id: aiTagSuggestionAITagReport(fileID: second.id, suggestions: [
                    aiTagSuggestionAITagSuggestion(id: "ai-tag-fail", slug: "tax", confidence: 0.89)
                ])
            ],
            applyReports: [
                first.id: aiTagSuggestionBatchApplyReport(fileID: first.id, suggestionID: "ai-tag-ok", slug: "finance"),
                second.id: aiTagSuggestionBatchApplyReport(
                    fileID: second.id,
                    suggestionID: "ai-tag-fail",
                    slug: "tax",
                    status: .failed,
                    error: "Tag relation write failed."
                )
            ]
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: [first, second]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([first.id, second.id])
        await model.loadBatchAITagSuggestions(files: [first, second])
        model.confirmBatchAITagSuggestions()
        await model.applyBatchAITagSuggestions()
        let review = model.aiTagBatchSuggestionState.review

        XCTAssertEqual(review?.appliedFileCount, 1)
        XCTAssertEqual(review?.failedFileCount, 1)
        XCTAssertEqual(review?.selectedIDsByFileID[first.id], Set<String>())
        XCTAssertEqual(review?.selectedIDsByFileID[second.id], Set(["ai-tag-fail"]))
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreBatchRejectingInvalidSuggestionClearsApplyBlocker() {
        let file = FileEntrySnapshot.detailMetaFixture(id: 719, currentName: "invoice-invalid.pdf")
        let report = aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
            aiTagSuggestionAITagSuggestion(id: "ai-tag-good", slug: "finance", confidence: 0.92),
            aiTagSuggestionAITagSuggestion(
                id: "ai-tag-invalid",
                slug: "",
                confidence: 0.88,
                status: .invalid,
                disabledReason: "Tag name is invalid."
            )
        ])
        var review = AITagBatchSuggestionAction.initialReview(
            files: [file],
            reports: [file.id: report],
            loadFailures: [:]
        )
        review.selectedIDsByFileID[file.id] = ["ai-tag-good", "ai-tag-invalid"]
        let blocked = AITagBatchSuggestionState.reviewing(review)

        XCTAssertFalse(review.canApply)
        XCTAssertEqual(review.invalidCount, 1)

        let unblocked = AITagBatchSuggestionAction.toggling(
            fileID: file.id,
            suggestionID: "ai-tag-invalid",
            in: blocked
        )

        XCTAssertEqual(unblocked.review?.selectedIDsByFileID[file.id], ["ai-tag-good"])
        XCTAssertEqual(unblocked.review?.reports[file.id]?.suggestions.map(\.suggestionId), ["ai-tag-good"])
        XCTAssertEqual(unblocked.review?.rejectedFeedback.first?.rejectedIDs, ["ai-tag-invalid"])
        XCTAssertEqual(unblocked.review?.invalidCount, 0)
        XCTAssertEqual(unblocked.review?.canApply, true)
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreBatchRejectSelectedHidesSuggestionsAndDoesNotApply() async {
        let files = [
            FileEntrySnapshot.detailMetaFixture(id: 722, currentName: "invoice-reject-a.pdf"),
            FileEntrySnapshot.detailMetaFixture(id: 723, currentName: "invoice-reject-b.pdf")
        ]
        let bridge = AITagSuggestionBatchAITagBridge(reports: [
            files[0].id: aiTagSuggestionAITagReport(fileID: files[0].id, suggestions: [
                aiTagSuggestionAITagSuggestion(id: "ai-tag-finance-a", slug: "finance", confidence: 0.93)
            ]),
            files[1].id: aiTagSuggestionAITagReport(fileID: files[1].id, suggestions: [
                aiTagSuggestionAITagSuggestion(id: "ai-tag-tax-b", slug: "tax", confidence: 0.89)
            ])
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: files),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles(Set(files.map(\.id)))
        await model.loadBatchAITagSuggestions(files: files)
        model.clearBatchAITagSuggestions()
        let review = model.aiTagBatchSuggestionState.review

        XCTAssertEqual(review?.selectedTagCount, 0)
        XCTAssertEqual(review?.reports[files[0].id]?.suggestions, [])
        XCTAssertEqual(review?.reports[files[1].id]?.suggestions, [])
        XCTAssertEqual(review?.rejectedFeedback.count, 2)
        await bridge.assertNoApplyRequests()
    }

    @MainActor
    func testAITagSuggestionAIPrivacyRulesCoreProviderScopeAndRemoteGateBlockBeforeAITagSuggestion() async {
        // swiftlint:disable:next large_tuple
        let cases: [(Int64, AiPrivacySkippedReason, AiPrivacyProviderGateReason)] = [
            (730, .providerNotVerified, .providerNotVerified),
            (731, .scopeNotAllowed, .scopeNotAllowed),
            (732, .providerDisabled, .providerDisabled)
        ]

        for item in cases {
            let file = FileEntrySnapshot.detailMetaFixture(id: item.0, currentName: "invoice-gated.pdf")
            let bridge = AITagSuggestionBatchAITagBridge(reports: [
                file.id: aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
                    aiTagSuggestionAITagSuggestion(id: "ai-tag-finance", slug: "finance", confidence: 0.91)
                ])
            ])
            let privacy = RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags]),
                evaluationReport: aiTagSuggestionProviderGateReport(
                    skippedReason: item.1,
                    providerGateReason: item.2
                )
            )
            let model = MainFileListModel(
                opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
                fileLister: NoopFileLister(),
                fileDetailer: DetailTagFileDetailer(files: [file]),
                aiSettingsLoader: AITagSuggestionAISettingsLoader(),
                aiTagSuggestionStore: bridge,
                aiPrivacyRules: privacy,
                errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
            )

            await model.selectFiles([file.id])
            await model.loadSelectedFileAITagSuggestions()

            await bridge.assertNoRequests()
            await privacy.assertEvaluationFeatures([.autoTags])
            XCTAssertEqual(model.aiTagSuggestionState.report?.status, .skipped)
            XCTAssertEqual(model.aiTagSuggestionState.report?.skippedReason, .providerUnavailable)
        }
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreBatchEditedMergeSuggestionAppliesEditedRequest() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 720, currentName: "invoice-merge.pdf")
        let unchangedFile = FileEntrySnapshot.detailMetaFixture(id: 721, currentName: "invoice-context.pdf")
        let bridge = Self.aiTagMergeBridge(file: file, unchangedFile: unchangedFile)
        let model = Self.aiTagMergeModel(file: file, unchangedFile: unchangedFile, bridge: bridge)

        await model.selectFiles([file.id, unchangedFile.id])
        await model.loadBatchAITagSuggestions(files: [file, unchangedFile])
        model.startEditingBatchAITagSuggestion(fileID: file.id, suggestionID: "ai-tag-merge")
        model.updateBatchAITagSuggestionDisplayName(
            fileID: file.id,
            suggestionID: "ai-tag-merge",
            displayName: "Finance Review"
        )
        model.updateBatchAITagSuggestionSlug(
            fileID: file.id,
            suggestionID: "ai-tag-merge",
            slug: "finance-review"
        )
        model.confirmBatchAITagSuggestions()
        await model.applyBatchAITagSuggestions()

        await bridge.assertSuggestFileIDs([file.id, unchangedFile.id])
        await bridge.assertSingleApplyRequest(
            fileID: file.id,
            confirmed: true,
            suggestionIDs: ["ai-tag-merge"],
            firstSuggestionDisplayName: "Finance Review",
            firstSuggestionSlug: "finance-review",
            firstSuggestionEditedByUser: true,
            firstSuggestionMergeTargetSlug: "finance"
        )
    }
}
