@testable import AreaMatrix
import XCTest

final class StartupRecoveryPageFeatureTests: XCTestCase {
    @MainActor
    func testStartupRecoveryStartupRecoveryCoreStartupRecoveryViewExposesReportRetryAndTechnicalDetails() {
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept active staging file"]
        )
        let completedView = StartupRecoveryErrorRecoveryView(
            state: .completed(report),
            onRetry: {}
        )
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.startupRecoveryStartupRecoveryMapping(rawContext: "recovery db locked")),
            onRetry: {}
        )
        let completedBody = startupRecoveryMirrorDescription(of: completedView.body)
        let failedBody = startupRecoveryMirrorDescription(of: failedView.body)

        assertTestDescription(completedBody, contains: [
            "Startup recovery complete",
            "启动恢复已完成",
            "startup-recovery-startup-recovery-core-startup-recovery",
            "startup-recovery-startup-recovery-core-recovery-report"
        ])
        assertTestDescription(failedBody, contains: [
            "Startup recovery failed",
            "Retry startup recovery",
            "startup-recovery-startup-recovery-core-retry-startup-recovery",
            "ErrorRecoveryMappedErrorView"
        ])
        assertTestDescription(failedBody, doesNotContain: [
            "Open repair",
            "Remove from index"
        ])
    }

    @MainActor
    func testStartupRecoveryErrorMappingCoreMappedErrorViewShowsCoreMappingWithoutHighRiskActions() {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryStartupRecoveryMapping(rawContext: "database is locked")
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "startup-recovery-error-mapping-retry",
            onRetry: {}
        )
        let body = startupRecoveryMirrorDescription(of: view.body)

        assertTestDescription(body, contains: [
            "startup-recovery-error-mapping-error-mapping",
            "Startup recovery could not finish",
            "Severity: Medium",
            "Recoverability: Retryable",
            "database is locked",
            "startup-recovery-error-mapping-retry"
        ])
        assertTestDescription(body, doesNotContain: [
            "Open repair",
            "Remove from index",
            "Download & retry"
        ])
    }

    @MainActor
    func testStartupRecoveryErrorMappingCoreMappedErrorViewFallsBackWhenCoreMappingOmitsOptionalText() {
        let mapping = CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "AreaMatrix hit an internal error.",
            severity: .critical,
            suggestedAction: "",
            recoverability: .fatal,
            rawContext: ""
        )
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "startup-recovery-error-mapping-retry",
            onRetry: {}
        )
        let body = startupRecoveryMirrorDescription(of: view.body)

        assertTestDescription(body, contains: [
            "Internal",
            "Severity: Critical",
            "Recoverability: Fatal",
            "Retry the failed action or collect diagnostics from the source page.",
            "No technical context was provided by Core."
        ])
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreStartupRecoveryRetryShowsInFlightButtonState() {
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.startupRecoveryStartupRecoveryMapping(rawContext: "recovery db locked")),
            isRetrying: true,
            onRetry: {}
        )
        let failedBody = startupRecoveryMirrorDescription(of: failedView.body)

        XCTAssertTrue(failedView.retryButtonTitle == "Retrying...")
        XCTAssertTrue(failedView.retryButtonIsDisabled)
        assertTestDescription(failedBody, contains: ["Retrying..."])
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreRecoveryFailureBlocksRepositoryOpenAndRetryRerunsCoreRecovery() async {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryStartupRecoveryMapping(rawContext: "database is locked")
        let recoverer = MainLoadingRecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database is locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 1, revertedStagingDbRows: 2, warnings: []))
        ])
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: ShellRecordingSettingsWriter(),
            pathValidator: MainLoadingStaticPathValidator(),
            initializedPathValidator: StaticInitializedPathValidator(),
            emptyRepositoryOpener: opener,
            startupRecoverer: recoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: StartupRecoveryErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)
        let openedBeforeRetry = await opener.requestedConfiguredRepoPaths()
        let requestsBeforeRetry = await recoverer.requestedRepoPaths()

        XCTAssertEqual(openedBeforeRetry, [])
        XCTAssertEqual(requestsBeforeRetry, ["/tmp/repo"])
        guard case let .mainLoading(failedState) = model.route else {
            return XCTFail("Expected startup-recovery startup recovery to stay in main loading")
        }
        XCTAssertEqual(failedState.recoveryErrorMapping, mapping)
        XCTAssertEqual(failedState.recoveryStatusText, "启动恢复失败：Startup recovery could not finish")

        let retryTask = Task {
            await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")
        }
        await opener.waitUntilStarted()
        let requestsAfterRetryStarted = await recoverer.requestedRepoPaths()
        let openedAfterRetryStarted = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(requestsAfterRetryStarted, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(openedAfterRetryStarted, ["/tmp/repo"])

        await opener.finishOpen()
        await retryTask.value
        XCTAssertEqual(model.route, .mainList(.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)))
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreDefaultCoreBridgeUsesGeneratedRecoverOnStartupBoundary() async throws {
        let repoURL = try startupRecoveryTemporaryDirectory()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let report = try await bridge.recoverOnStartup(repoPath: repoURL.path)

        XCTAssertFalse(report.hasVisibleDetails)
    }
}

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
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.tagSuggestionsApplied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles(Set(files.map(\.id)))
        await model.loadBatchAITagSuggestions(files: files)
        let beforeConfirm = await bridge.requests()
        model.confirmBatchAITagSuggestions()
        let afterConfirm = await bridge.requests()
        await model.applyBatchAITagSuggestions()
        let afterApply = await bridge.requests()

        XCTAssertEqual(beforeConfirm.suggest.map(\.fileId).sorted(), [707, 708])
        XCTAssertEqual(beforeConfirm.apply, [])
        XCTAssertEqual(afterConfirm.apply, [])
        XCTAssertEqual(afterApply.apply.map(\.fileId).sorted(), [707, 708])
        XCTAssertTrue(afterApply.apply.allSatisfy(\.confirmed))
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
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: [first, second]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: DetailMetaErrorMapper(mapping: .tagAddTagDb())
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
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: DetailMetaErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles(Set(files.map(\.id)))
        await model.loadBatchAITagSuggestions(files: files)
        model.clearBatchAITagSuggestions()
        let requests = await bridge.requests()
        let review = model.aiTagBatchSuggestionState.review

        XCTAssertEqual(review?.selectedTagCount, 0)
        XCTAssertEqual(review?.reports[files[0].id]?.suggestions, [])
        XCTAssertEqual(review?.reports[files[1].id]?.suggestions, [])
        XCTAssertEqual(review?.rejectedFeedback.count, 2)
        XCTAssertEqual(requests.apply, [])
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
                fileLister: DetailMetaNoopLister(),
                fileDetailer: DetailTagFileDetailer(files: [file]),
                aiSettingsLoader: AITagSuggestionAISettingsLoader(),
                aiTagSuggestionStore: bridge,
                aiPrivacyRules: privacy,
                errorMapper: DetailMetaErrorMapper(mapping: .tagAddTagDb())
            )

            await model.selectFiles([file.id])
            await model.loadSelectedFileAITagSuggestions()
            let aiRequests = await bridge.requests()
            let privacyRequests = await privacy.requests()

            XCTAssertEqual(aiRequests.suggest, [])
            XCTAssertEqual(aiRequests.apply, [])
            XCTAssertEqual(privacyRequests.evaluations.map(\.feature), [.autoTags])
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
        let requests = await bridge.requests()

        XCTAssertEqual(requests.suggest.map(\.fileId).sorted(), [file.id, unchangedFile.id])
        XCTAssertEqual(requests.apply.count, 1)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.suggestions.first?.suggestionId, "ai-tag-merge")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.displayName, "Finance Review")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.slug, "finance-review")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.editedByUser, true)
        XCTAssertEqual(requests.apply.first?.suggestions.first?.mergeTargetSlug, "finance")
    }
}

private actor StartupRecoveryErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private actor StaticInitializedPathValidator: CoreInitializedRepositoryPathValidating {
    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private actor MainLoadingStaticPathValidator: CoreRepositoryPathValidating {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private extension CoreErrorMappingSnapshot {
    static func startupRecoveryStartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            suggestedAction: "Retry startup recovery before opening the repository.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private func startupRecoveryTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixStartupRecoveryStartupRecovery")
}

private func startupRecoveryMirrorDescription(of value: Any) -> String {
    testMirrorDescription(of: value)
}
