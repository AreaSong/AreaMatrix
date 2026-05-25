@testable import AreaMatrix
import XCTest

final class ClassifierSettingsRecoveryTests: XCTestCase {
    @MainActor
    func testCreateDefaultClassifierYamlCreatesOnlyMetadataFileAndStoresBackup() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".areamatrix", isDirectory: true),
            withIntermediateDirectories: true
        )
        let predictor = ClassifierSettingsSequencePredictor(results: [.success(classifierRecoveryProbeResult())])
        let model = await recoveryModel(repoURL: repoURL, predictor: predictor)

        await model.createDefaultClassifierYaml()

        let classifierURL = classifierURL(repoURL: repoURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: classifierURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastValidBackupURL(repoURL: repoURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
        XCTAssertEqual(model.validationState, .passed)
        XCTAssertTrue(model.canRevertToLastValid)
        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsSequencePredictor.Request(
                repoPath: repoURL.path,
                filename: "AreaMatrixValidationProbe.txt"
            )
        ])
    }

    @MainActor
    func testCreateDefaultClassifierYamlDoesNotOverwriteExistingRules() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let existing = "version: 1\ndefault: inbox\ncategories: []\n"
        try writeClassifier(existing, repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [.success(classifierRecoveryProbeResult())])
        let model = await recoveryModel(repoURL: repoURL, predictor: predictor)

        await model.createDefaultClassifierYaml()

        XCTAssertEqual(try String(contentsOf: classifierURL(repoURL: repoURL), encoding: .utf8), existing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lastValidBackupURL(repoURL: repoURL).path))
        XCTAssertEqual(model.fileActionError?.message, "无法创建默认分类规则文件")
        let requests = await predictor.requests()
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testValidateStoresLastValidBackupAndRevertRestoresThatContent() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let original = """
        version: 1
        default: inbox
        categories:
          - slug: inbox
            display_name: { en: Inbox }
        """
        try writeClassifier(original, repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .success(classifierRecoveryProbeResult()),
            .success(classifierRecoveryProbeResult())
        ])
        let model = await recoveryModel(repoURL: repoURL, predictor: predictor)

        let validated = await model.validateClassifierRules()
        try writeClassifier("version: 1\ndefault: broken\ncategories: []\n", repoURL: repoURL)
        await model.revertToLastValid()

        XCTAssertTrue(validated)
        XCTAssertEqual(try String(contentsOf: classifierURL(repoURL: repoURL), encoding: .utf8), original)
        XCTAssertEqual(try String(contentsOf: lastValidBackupURL(repoURL: repoURL), encoding: .utf8), original)
        XCTAssertEqual(model.validationState, .passed)
        XCTAssertTrue(model.canRevertToLastValid)
        let requests = await predictor.requests()
        XCTAssertEqual(requests.count, 2)
    }

    @MainActor
    func testValidationFailureShowsLineFieldAndErrorText() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try writeClassifier("version: 1\ndefault: inbox\ncategories: []\n", repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .failure(CoreError.Config(reason: "categories[2].slug duplicate at line 47 column 5"))
        ])
        let model = await recoveryModel(repoURL: repoURL, predictor: predictor)

        let validated = await model.validateClassifierRules()

        XCTAssertFalse(validated)
        XCTAssertEqual(model.validationStatusLabel, "Failed")
        XCTAssertEqual(
            model.validationError?.message,
            "分类规则无效：categories[2].slug duplicate at line 47 column 5 (field categories[2].slug, line 47)"
        )
        XCTAssertEqual(model.validationError?.recovery, "Open classifier.yaml and fix the reported line and field.")
    }

    @MainActor
    func testS219RuleEditorUpdatesExistingRuleThroughCoreCrudAfterValidation() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "finance"))
        )
        let model = await recoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        var draft = try XCTUnwrap(model.classifierRuleEditor.draft)
        draft.displayName = "Finance Rules"
        model.updateClassifierRuleDraft(draft)
        model.addClassifierRuleExtension(".PDF")
        model.addClassifierRuleKeyword("invoice")

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        model.validateClassifierRuleDraft()
        XCTAssertTrue(model.classifierRuleEditor.canSave)

        await model.saveClassifierRuleDraft()

        let lists = await editor.listRequests()
        let updates = await editor.updateRequests()
        XCTAssertEqual(lists, [repoURL.path])
        XCTAssertEqual(updates.first?.repoPath, repoURL.path)
        XCTAssertEqual(updates.first?.request.ruleID, "finance")
        XCTAssertEqual(updates.first?.request.displayName, "Finance Rules")
        XCTAssertEqual(updates.first?.request.extensions, ["pdf"])
        XCTAssertEqual(updates.first?.request.keywords, ["invoice"])
        XCTAssertTrue(updates.first?.request.previewConfirmed ?? false)
        XCTAssertEqual(model.classifierRuleEditor.saveState, .saved("finance"))
    }

    @MainActor
    func testS219NewCategoryUsesCreateCrudAndRequiresValidate() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "tax"))
        )
        let model = await recoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.createClassifierRule()
        var draft = try XCTUnwrap(model.classifierRuleEditor.draft)
        draft.slug = "tax"
        draft.displayName = "Tax"
        draft.description = "Tax documents"
        draft.priority = 10
        draft.namingTemplate = "{stem}-{date}"
        model.updateClassifierRuleDraft(draft)
        model.addClassifierRuleExtension("pdf")

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        model.validateClassifierRuleDraft()
        await model.saveClassifierRuleDraft()

        let creates = await editor.createRequests()
        XCTAssertEqual(creates.first?.request.slug, "tax")
        XCTAssertEqual(creates.first?.request.displayName, "Tax")
        XCTAssertEqual(creates.first?.request.extensions, ["pdf"])
        XCTAssertEqual(creates.first?.request.namingTemplate, "{stem}-{date}")
    }

    @MainActor
    func testS219DeleteRuleUsesCrudWithoutMovingHistoricalFiles() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "docs"))
        )
        let model = await recoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        model.requestDeleteSelectedClassifierRule()
        var deletes = await editor.deleteRequests()
        XCTAssertTrue(deletes.isEmpty)

        await model.confirmDeleteSelectedClassifierRule()

        deletes = await editor.deleteRequests()
        XCTAssertEqual(deletes.first?.repoPath, repoURL.path)
        XCTAssertEqual(deletes.first?.request.ruleID, "finance")
        XCTAssertEqual(deletes.first?.request.replacementCategory, "docs")
        XCTAssertTrue(deletes.first?.request.previewConfirmed ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testS219RemovingMatcherRequiresImpactSummaryBeforeSave() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(listResult: .success(.classifierEditorFixture()))
        let model = await recoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        model.requestRemoveClassifierRuleExtension("pdf")
        model.validateClassifierRuleDraft()

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        XCTAssertNotNil(model.classifierRuleEditor.pendingMatcherRemoval)
        XCTAssertEqual(model.classifierRuleEditor.draft?.extensions, ["pdf"])

        model.confirmClassifierRuleImpactSummary()
        model.validateClassifierRuleDraft()

        XCTAssertTrue(model.classifierRuleEditor.canSave)
        XCTAssertNil(model.classifierRuleEditor.pendingMatcherRemoval)
        XCTAssertEqual(model.classifierRuleEditor.draft?.extensions, [])
    }

    @MainActor
    private func recoveryModel(
        repoURL: URL,
        predictor: any CoreCategoryPredicting,
        editor: any CoreClassifierRuleEditing = ClassifierSettingsRecordingRuleEditor()
    ) async -> ClassifierSettingsModel {
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: ClassifierSettingsRecoveryLoader(config: .classifierRecoveryFixture(repoPath: repoURL.path)),
            updater: ClassifierSettingsRecoveryUpdater(),
            predictor: predictor,
            ruleEditor: editor,
            errorMapper: ClassifierSettingsRecoveryErrorMapper(),
            accessibilityAnnouncer: ClassifierSettingsRecoveryNoopAnnouncer()
        )
        await model.load()
        return model
    }
}

private struct ClassifierSettingsRecoveryNoopAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}

private enum ClassifierSequencePredictorResult {
    case success(ClassifyResultSnapshot)
    case failure(Error)
}

private actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private var results: [ClassifierSequencePredictorResult]
    private var requestsStorage: [Request] = []

    init(results: [ClassifierSequencePredictorResult] = [.success(classifierRecoveryProbeResult())]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(Request(repoPath: repoPath, filename: filename))
        let result = results.isEmpty ? .success(classifierRecoveryProbeResult()) : results.removeFirst()
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [Request] {
        requestsStorage
    }
}

private enum ClassifierRuleEditorResult {
    case success(ClassifierRuleEditorSnapshotState)
    case failure(Error)
}

private actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
    typealias CreateRequest = (repoPath: String, request: ClassifierRuleCreateRequestSnapshot)
    typealias UpdateRequest = (repoPath: String, request: ClassifierRuleUpdateSnapshot)
    typealias DeleteRequest = (repoPath: String, request: ClassifierRuleDeleteRequestSnapshot)

    private let listResult: ClassifierRuleEditorResult
    private let mutationResult: ClassifierRuleEditorResult
    private var listRequestsStorage: [String] = []
    private var createRequestsStorage: [CreateRequest] = []
    private var updateRequestsStorage: [UpdateRequest] = []
    private var deleteRequestsStorage: [DeleteRequest] = []

    init(
        listResult: ClassifierRuleEditorResult = .success(.classifierEditorFixture()),
        mutationResult: ClassifierRuleEditorResult = .success(.classifierEditorFixture())
    ) {
        self.listResult = listResult
        self.mutationResult = mutationResult
    }

    func listClassifierRules(repoPath: String) async throws -> ClassifierRuleEditorSnapshotState {
        listRequestsStorage.append(repoPath)
        return try resolve(listResult)
    }

    func createClassifierRule(
        repoPath: String,
        request: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        createRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func updateClassifierRule(
        repoPath: String,
        request: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        updateRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func deleteClassifierRule(
        repoPath: String,
        request: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        deleteRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func listRequests() -> [String] {
        listRequestsStorage
    }

    func createRequests() -> [CreateRequest] {
        createRequestsStorage
    }

    func updateRequests() -> [UpdateRequest] {
        updateRequestsStorage
    }

    func deleteRequests() -> [DeleteRequest] {
        deleteRequestsStorage
    }

    private func resolve(_ result: ClassifierRuleEditorResult) throws -> ClassifierRuleEditorSnapshotState {
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}

private actor ClassifierSettingsRecoveryLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor ClassifierSettingsRecoveryUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private actor ClassifierSettingsRecoveryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case let .Config(reason):
            .classifierRecoveryMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
        default:
            .classifierRecoveryMapping(kind: .internal, userMessage: "分类规则校验失败")
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func classifierRecoveryMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Open classifier.yaml",
            recoverability: .userActionRequired,
            rawContext: kind.rawValue
        )
    }
}

private extension RepoConfigSnapshot {
    static func classifierRecoveryFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension ClassifierRuleEditorSnapshotState {
    static func classifierEditorFixture(updatedRuleID: String? = nil) -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                ClassifierRuleRecordSnapshot(
                    ruleID: "docs",
                    slug: "docs",
                    displayName: "Documents",
                    description: "Docs",
                    extensions: ["md"],
                    keywords: ["report"],
                    priority: 0,
                    namingTemplate: nil,
                    isDefault: true
                ),
                ClassifierRuleRecordSnapshot(
                    ruleID: "finance",
                    slug: "finance",
                    displayName: "Finance",
                    description: "Finance docs",
                    extensions: ["pdf"],
                    keywords: [],
                    priority: 10,
                    namingTemplate: nil,
                    isDefault: false
                )
            ],
            defaultRuleID: "docs",
            updatedRuleID: updatedRuleID,
            warning: nil
        )
    }
}

private func classifierRecoveryProbeResult() -> ClassifyResultSnapshot {
    ClassifyResultSnapshot(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
}

private func temporaryClassifierRecoveryRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixClassifierRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func classifierURL(repoURL: URL) -> URL {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
}

private func lastValidBackupURL(repoURL: URL) -> URL {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.last-valid.yaml", isDirectory: false)
}

private func writeClassifier(_ content: String, repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try content.write(to: classifierURL(repoURL: repoURL), atomically: true, encoding: .utf8)
}
