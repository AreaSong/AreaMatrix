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
        loader: StaticConfigurationLoader(config: .classifierRecoveryFixture(repoPath: repoURL.path)),
        updater: NoopConfigurationUpdater(),
        predictor: predictor,
        ruleEditor: editor,
        errorMapper: ClassifierSettingsRecoveryErrorMapper(),
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
    )
    await model.load()
    return model
}

actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private var results: [Swift.Result<ClassifyResultSnapshot, Error>]
    private var requestsStorage: [Request] = []

    init(
        results: [Swift.Result<ClassifyResultSnapshot, Error>] = [
            .success(classifierSettingsValidationProbeResult())
        ]
    ) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(Request(repoPath: repoPath, filename: filename))
        let result = results.isEmpty ? .success(classifierSettingsValidationProbeResult()) : results.removeFirst()
        return try result.get()
    }

    func requests() -> [Request] {
        requestsStorage
    }
}

actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
    typealias CreateRequest = (repoPath: String, request: ClassifierRuleCreateRequestSnapshot)
    typealias UpdateRequest = (repoPath: String, request: ClassifierRuleUpdateSnapshot)
    typealias DeleteRequest = (repoPath: String, request: ClassifierRuleDeleteRequestSnapshot)

    private let listResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error>
    private let mutationResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error>
    private var listRequestsStorage: [String] = []
    private var createRequestsStorage: [CreateRequest] = []
    private var updateRequestsStorage: [UpdateRequest] = []
    private var deleteRequestsStorage: [DeleteRequest] = []

    init(
        listResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture()),
        mutationResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture())
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

    private func resolve(_ result: Swift.Result<ClassifierRuleEditorSnapshotState, Error>)
        throws -> ClassifierRuleEditorSnapshotState {
        try result.get()
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

final class ClassifierSettingsTestRulesManager: ClassifierRulesManaging {
    private let fileManager = FileManager.default

    func classifierFileExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: classifierFileURL(repoPath: repoPath).path)
    }

    func classifierCategorySlugs(repoPath: String) throws -> [String] {
        let yaml = try String(contentsOf: classifierFileURL(repoPath: repoPath), encoding: .utf8)
        return ClassifierRulesCategorySlugParser.slugs(in: yaml)
    }

    func lastValidBackupExists(repoPath: String) -> Bool {
        fileManager.fileExists(atPath: lastValidBackupFileURL(repoPath: repoPath).path)
    }

    func createDefaultClassifier(repoPath _: String) throws {}

    func storeLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: classifierFileURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: lastValidBackupFileURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func restoreLastValidBackup(repoPath: String) throws {
        let yaml = try String(contentsOf: lastValidBackupFileURL(repoPath: repoPath), encoding: .utf8)
        try yaml.write(to: classifierFileURL(repoPath: repoPath), atomically: true, encoding: .utf8)
    }

    func writeClassifier(repoURL: URL, slugs: [String]) throws {
        let yaml = """
        version: 1
        default: inbox
        categories:
        \(slugs.map { "  - slug: \($0)" }.joined(separator: "\n"))
        """
        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try yaml.write(to: classifierFileURL(repoPath: repoURL.path), atomically: true, encoding: .utf8)
    }

    private func classifierFileURL(repoPath: String) -> URL {
        classifierURL(repoURL: URL(fileURLWithPath: repoPath, isDirectory: true))
    }

    private func lastValidBackupFileURL(repoPath: String) -> URL {
        lastValidBackupURL(repoURL: URL(fileURLWithPath: repoPath, isDirectory: true))
    }
}

extension RecordingCoreErrorMapper {
    static func classifierSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            switch error {
            case .Db:
                .classifierSettingsMapping(kind: .db, userMessage: "数据库错误")
            case let .Config(reason):
                .classifierSettingsMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
            case let .Classify(reason):
                .classifierSettingsMapping(kind: .classify, userMessage: "无法预览分类：\(reason)")
            case .PermissionDenied:
                .classifierSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
            default:
                .classifierSettingsMapping(kind: .internal, userMessage: "保存失败")
            }
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func classifierSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }
}
