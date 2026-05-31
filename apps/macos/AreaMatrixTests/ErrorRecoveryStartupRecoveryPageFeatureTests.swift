@testable import AreaMatrix
import XCTest

final class StartupRecoveryPageFeatureTests: XCTestCase {
    @MainActor
    func testS132C116StartupRecoveryViewExposesReportRetryAndTechnicalDetails() {
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
            state: .failed(.s132StartupRecoveryMapping(rawContext: "recovery db locked")),
            onRetry: {}
        )
        let completedBody = s132MirrorDescription(of: completedView.body)
        let failedBody = s132MirrorDescription(of: failedView.body)

        XCTAssertTrue(completedBody.contains("Startup recovery complete"))
        XCTAssertTrue(completedBody.contains("启动恢复已完成"))
        XCTAssertTrue(completedBody.contains("S1-32-C1-16-startup-recovery"))
        XCTAssertTrue(completedBody.contains("S1-32-C1-16-recovery-report"))
        XCTAssertTrue(failedBody.contains("Startup recovery failed"))
        XCTAssertTrue(failedBody.contains("Retry startup recovery"))
        XCTAssertTrue(failedBody.contains("S1-32-C1-16-retry-startup-recovery"))
        XCTAssertTrue(failedBody.contains("ErrorRecoveryMappedErrorView"))
        XCTAssertFalse(failedBody.contains("Open repair"))
        XCTAssertFalse(failedBody.contains("Remove from index"))
    }

    @MainActor
    func testS132C121MappedErrorViewShowsCoreMappingWithoutHighRiskActions() {
        let mapping = CoreErrorMappingSnapshot.s132StartupRecoveryMapping(rawContext: "database is locked")
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "S1-32-C1-21-retry",
            onRetry: {}
        )
        let body = s132MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("S1-32-C1-21-error-mapping"))
        XCTAssertTrue(body.contains("Startup recovery could not finish"))
        XCTAssertTrue(body.contains("Severity: Medium"))
        XCTAssertTrue(body.contains("Recoverability: Retryable"))
        XCTAssertTrue(body.contains("database is locked"))
        XCTAssertTrue(body.contains("S1-32-C1-21-retry"))
        XCTAssertFalse(body.contains("Open repair"))
        XCTAssertFalse(body.contains("Remove from index"))
        XCTAssertFalse(body.contains("Download & retry"))
    }

    @MainActor
    func testS132C121MappedErrorViewFallsBackWhenCoreMappingOmitsOptionalText() {
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
            retryAccessibilityIdentifier: "S1-32-C1-21-retry",
            onRetry: {}
        )
        let body = s132MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("Internal"))
        XCTAssertTrue(body.contains("Severity: Critical"))
        XCTAssertTrue(body.contains("Recoverability: Fatal"))
        XCTAssertTrue(body.contains("Retry the failed action or collect diagnostics from the source page."))
        XCTAssertTrue(body.contains("No technical context was provided by Core."))
    }

    @MainActor
    func testS132C116StartupRecoveryRetryShowsInFlightButtonState() {
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.s132StartupRecoveryMapping(rawContext: "recovery db locked")),
            isRetrying: true,
            onRetry: {}
        )
        let failedBody = s132MirrorDescription(of: failedView.body)

        XCTAssertTrue(failedView.retryButtonTitle == "Retrying...")
        XCTAssertTrue(failedView.retryButtonIsDisabled)
        XCTAssertTrue(failedBody.contains("Retrying..."))
    }

    @MainActor
    func testS132C116RecoveryFailureBlocksRepositoryOpenAndRetryRerunsCoreRecovery() async {
        let mapping = CoreErrorMappingSnapshot.s132StartupRecoveryMapping(rawContext: "database is locked")
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
            errorMapper: S132StartupRecoveryErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)
        let openedBeforeRetry = await opener.requestedConfiguredRepoPaths()
        let requestsBeforeRetry = await recoverer.requestedRepoPaths()

        XCTAssertEqual(openedBeforeRetry, [])
        XCTAssertEqual(requestsBeforeRetry, ["/tmp/repo"])
        guard case let .mainLoading(failedState) = model.route else {
            return XCTFail("Expected S1-32 startup recovery to stay in main loading")
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
    func testS132C116DefaultCoreBridgeUsesGeneratedRecoverOnStartupBoundary() async throws {
        let repoURL = try s132TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let report = try await bridge.recoverOnStartup(repoPath: repoURL.path)

        XCTAssertFalse(report.hasVisibleDetails)
    }
}

final class S307AITagBatchPageFeatureTests: XCTestCase {
    @MainActor
    func testS307C307BatchReviewConfirmsBeforeApplyingTags() async {
        let files = [
            FileEntrySnapshot.detailMetaFixture(id: 707, currentName: "invoice-a.pdf"),
            FileEntrySnapshot.detailMetaFixture(id: 708, currentName: "invoice-b.pdf")
        ]
        let bridge = S307BatchAITagBridge(reports: Dictionary(uniqueKeysWithValues: files.map {
            ($0.id, s307AITagReport(fileID: $0.id, suggestions: [
                s307AITagSuggestion(id: "s3-07-finance-\($0.id)", slug: "finance", confidence: 0.91)
            ]))
        }))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: files),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
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
    func testS307C307BatchPartialFailureKeepsFailedSuggestionsPending() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 717, currentName: "invoice-ok.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 718, currentName: "invoice-fail.pdf")
        let bridge = S307BatchAITagBridge(
            reports: [
                first.id: s307AITagReport(fileID: first.id, suggestions: [
                    s307AITagSuggestion(id: "s3-07-ok", slug: "finance", confidence: 0.93)
                ]),
                second.id: s307AITagReport(fileID: second.id, suggestions: [
                    s307AITagSuggestion(id: "s3-07-fail", slug: "tax", confidence: 0.89)
                ])
            ],
            applyReports: [
                first.id: s307BatchApplyReport(fileID: first.id, suggestionID: "s3-07-ok", slug: "finance"),
                second.id: s307BatchApplyReport(
                    fileID: second.id,
                    suggestionID: "s3-07-fail",
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
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([first.id, second.id])
        await model.loadBatchAITagSuggestions(files: [first, second])
        model.confirmBatchAITagSuggestions()
        await model.applyBatchAITagSuggestions()
        let review = model.aiTagBatchSuggestionState.review

        XCTAssertEqual(review?.appliedFileCount, 1)
        XCTAssertEqual(review?.failedFileCount, 1)
        XCTAssertEqual(review?.selectedIDsByFileID[first.id], Set<String>())
        XCTAssertEqual(review?.selectedIDsByFileID[second.id], Set(["s3-07-fail"]))
    }

    @MainActor
    func testS307C307BatchRejectingInvalidSuggestionClearsApplyBlocker() {
        let file = FileEntrySnapshot.detailMetaFixture(id: 719, currentName: "invoice-invalid.pdf")
        let report = s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-good", slug: "finance", confidence: 0.92),
            s307AITagSuggestion(
                id: "s3-07-invalid",
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
        review.selectedIDsByFileID[file.id] = ["s3-07-good", "s3-07-invalid"]
        let blocked = AITagBatchSuggestionState.reviewing(review)

        XCTAssertFalse(review.canApply)
        XCTAssertEqual(review.invalidCount, 1)

        let unblocked = AITagBatchSuggestionAction.toggling(
            fileID: file.id,
            suggestionID: "s3-07-invalid",
            in: blocked
        )

        XCTAssertEqual(unblocked.review?.selectedIDsByFileID[file.id], ["s3-07-good"])
        XCTAssertEqual(unblocked.review?.reports[file.id]?.suggestions.map(\.suggestionId), ["s3-07-good"])
        XCTAssertEqual(unblocked.review?.rejectedFeedback.first?.rejectedIDs, ["s3-07-invalid"])
        XCTAssertEqual(unblocked.review?.invalidCount, 0)
        XCTAssertEqual(unblocked.review?.canApply, true)
    }

    @MainActor
    func testS307C307BatchRejectSelectedHidesSuggestionsAndDoesNotApply() async {
        let files = [
            FileEntrySnapshot.detailMetaFixture(id: 722, currentName: "invoice-reject-a.pdf"),
            FileEntrySnapshot.detailMetaFixture(id: 723, currentName: "invoice-reject-b.pdf")
        ]
        let bridge = S307BatchAITagBridge(reports: [
            files[0].id: s307AITagReport(fileID: files[0].id, suggestions: [
                s307AITagSuggestion(id: "s3-07-finance-a", slug: "finance", confidence: 0.93)
            ]),
            files[1].id: s307AITagReport(fileID: files[1].id, suggestions: [
                s307AITagSuggestion(id: "s3-07-tax-b", slug: "tax", confidence: 0.89)
            ])
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: files),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: files),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
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
    func testS307C309ProviderScopeAndRemoteGateBlockBeforeAITagSuggestion() async {
        let cases: [(Int64, AiPrivacySkippedReason, AiPrivacyProviderGateReason)] = [
            (730, .providerNotVerified, .providerNotVerified),
            (731, .scopeNotAllowed, .scopeNotAllowed),
            (732, .providerDisabled, .providerDisabled)
        ]

        for item in cases {
            let file = FileEntrySnapshot.detailMetaFixture(id: item.0, currentName: "invoice-gated.pdf")
            let bridge = S307BatchAITagBridge(reports: [
                file.id: s307AITagReport(fileID: file.id, suggestions: [
                    s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91)
                ])
            ])
            let privacy = RemotePrivacyRulesBridge(
                snapshot: .s303PrivacyRules(featureScope: [.autoTags]),
                evaluationReport: s307ProviderGateReport(
                    skippedReason: item.1,
                    providerGateReason: item.2
                )
            )
            let model = MainFileListModel(
                opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
                fileLister: DetailMetaNoopLister(),
                fileDetailer: DetailTagFileDetailer(files: [file]),
                aiSettingsLoader: S307AISettingsLoader(),
                aiTagSuggestionStore: bridge,
                aiPrivacyRules: privacy,
                errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
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
    func testS307C307BatchEditedMergeSuggestionAppliesEditedRequest() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 720, currentName: "invoice-merge.pdf")
        let unchangedFile = FileEntrySnapshot.detailMetaFixture(id: 721, currentName: "invoice-context.pdf")
        let bridge = S307BatchAITagBridge(reports: [
            file.id: s307AITagReport(fileID: file.id, suggestions: [
                s307AITagSuggestion(
                    id: "s3-07-merge",
                    slug: "finances",
                    confidence: 0.91,
                    selectedByDefault: false,
                    displayName: "Finances",
                    mergeAction: .mergeWithExistingTag,
                    matchedExistingSlug: "finance"
                )
            ]),
            unchangedFile.id: s307AITagReport(fileID: unchangedFile.id, status: .noSuggestion)
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file, unchangedFile]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: [file, unchangedFile]),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id, unchangedFile.id])
        await model.loadBatchAITagSuggestions(files: [file, unchangedFile])
        model.startEditingBatchAITagSuggestion(fileID: file.id, suggestionID: "s3-07-merge")
        model.updateBatchAITagSuggestionDisplayName(
            fileID: file.id,
            suggestionID: "s3-07-merge",
            displayName: "Finance Review"
        )
        model.updateBatchAITagSuggestionSlug(
            fileID: file.id,
            suggestionID: "s3-07-merge",
            slug: "finance-review"
        )
        model.confirmBatchAITagSuggestions()
        await model.applyBatchAITagSuggestions()
        let requests = await bridge.requests()

        XCTAssertEqual(requests.suggest.map(\.fileId).sorted(), [file.id, unchangedFile.id])
        XCTAssertEqual(requests.apply.count, 1)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.suggestions.first?.suggestionId, "s3-07-merge")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.displayName, "Finance Review")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.slug, "finance-review")
        XCTAssertEqual(requests.apply.first?.suggestions.first?.editedByUser, true)
        XCTAssertEqual(requests.apply.first?.suggestions.first?.mergeTargetSlug, "finance")
    }
}

private actor S132StartupRecoveryErrorMapper: CoreErrorMapping {
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
    static func s132StartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
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

private func s132TemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS132StartupRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func s132MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS132MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS132MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS132MirrorDescription(of: child.value, to: &lines)
    }
}
