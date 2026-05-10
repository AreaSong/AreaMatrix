@testable import AreaMatrix
import XCTest

final class ValidatePathErrorMappingTests: XCTestCase {
    @MainActor
    func testValidatePathMapsCoreFailureThroughC121ErrorMapper() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokePermissionDeniedFixture(rawContext: "/tmp/repo")
        let errorMapper = ErrorSmokeRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertEqual(model.repositoryPathErrorMapping, mapping)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    func testCoreBridgeMapsCoreErrorThroughGeneratedBindings() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/restricted/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.userMessage, "无访问权限")
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertEqual(mapping.rawContext, "/restricted/repo")
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
    }

    @MainActor
    func testConfigValidationFailureRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokeConfigFixture(rawContext: "schema mismatch")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.Config(reason: "schema mismatch"))),
            errorMapper: ErrorSmokeRecordingErrorMapper(mapping: mapping),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class ValidatePathIntegrationSmokeTests: XCTestCase {
    @MainActor
    func testInsufficientCapacityBlocksValidatePathContinue() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: 128 * 1024 * 1024
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "可用空间不足，请释放空间或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

private final class ErrorSmokeRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var mappedErrors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mappedErrors.append(error)
        return mapping
    }
}

private extension CoreErrorMappingSnapshot {
    static func errorSmokePermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func errorSmokeConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库 schema 不兼容",
            severity: .critical,
            suggestedAction: "请选择其他资料库，或导出诊断信息",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
