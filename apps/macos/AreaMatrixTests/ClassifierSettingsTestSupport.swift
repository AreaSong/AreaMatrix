@testable import AreaMatrix
import Foundation

@MainActor
func classifierSettingsRecoveryModel(
    repoURL: URL,
    predictor: any CoreCategoryPredicting,
    editor: any CoreClassifierRuleEditing = ClassifierSettingsRecordingRuleEditor()
) async -> ClassifierSettingsModel {
    let model = ClassifierSettingsModel(
        repoPath: repoURL.path,
        loader: ClassifierSettingsRecoveryLoader(config: .classifierRecoveryFixture(repoPath: repoURL.path)),
        updater: NoopConfigurationUpdater(),
        predictor: predictor,
        ruleEditor: editor,
        errorMapper: ClassifierSettingsRecoveryErrorMapper(),
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
    )
    await model.load()
    return model
}

enum ClassifierSequencePredictorResult {
    case success(ClassifyResultSnapshot)
    case failure(Error)
}

actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
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

enum ClassifierRuleEditorResult {
    case success(ClassifierRuleEditorSnapshotState)
    case failure(Error)
}

actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
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

actor ClassifierSettingsRecoveryLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

actor ClassifierSettingsRecoveryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case let .Config(reason):
            .classifierRecoveryMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
        default:
            .classifierRecoveryMapping(kind: .internal, userMessage: "分类规则校验失败")
        }
    }
}

extension CoreErrorMappingSnapshot {
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

extension RepoConfigSnapshot {
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

extension ClassifierRuleEditorSnapshotState {
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

func classifierRecoveryProbeResult() -> ClassifyResultSnapshot {
    ClassifyResultSnapshot(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
}

func temporaryClassifierRecoveryRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierRecovery")
}

func classifierURL(repoURL: URL) -> URL {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
}

func lastValidBackupURL(repoURL: URL) -> URL {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.last-valid.yaml", isDirectory: false)
}

func writeClassifier(_ content: String, repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try content.write(to: classifierURL(repoURL: repoURL), atomically: true, encoding: .utf8)
}
