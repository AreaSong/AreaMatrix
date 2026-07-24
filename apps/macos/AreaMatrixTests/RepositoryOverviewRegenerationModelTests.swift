@testable import AreaMatrix
import XCTest

@MainActor
final class RepositoryOverviewRegenerationModelTests: XCTestCase {
    func testInitiatingWindowStagesAndCommitsWhileObserverRemainsReadOnly() async throws {
        let bridge = OverviewRegeneratorDouble()
        let coordinator = OverviewRegenerationCoordinator()
        let initiator = try RepositoryOverviewRegenerationModel(
            repoPath: "/tmp/repo",
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000010")),
            bridge: bridge,
            coordinator: coordinator,
            errorMapper: CoreBridge()
        )
        let observer = try RepositoryOverviewRegenerationModel(
            repoPath: "/tmp/repo",
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000020")),
            bridge: bridge,
            coordinator: coordinator,
            errorMapper: CoreBridge()
        )

        await initiator.load(contentLocale: "zh-Hans")
        await initiator.prepare()
        guard case .preflight = initiator.phase else {
            return XCTFail("expected preflight")
        }

        await initiator.stageConfirmedPlan()

        XCTAssertEqual(initiator.sharedOperation?.session.status, .readyToCommit)
        XCTAssertEqual(observer.sharedOperation?.session.status, .readyToCommit)
        XCTAssertTrue(initiator.canInteractWithSharedOperation)
        XCTAssertFalse(observer.canInteractWithSharedOperation)

        await observer.commit()
        let observerCommitCalls = await bridge.commitCallCount()
        XCTAssertEqual(observerCommitCalls, 0)

        await initiator.commit()
        let initiatorCommitCalls = await bridge.commitCallCount()
        XCTAssertEqual(initiatorCommitCalls, 1)
        XCTAssertEqual(initiator.sharedOperation?.session.status, .completed)
        XCTAssertEqual(observer.sharedOperation?.session.status, .completed)
    }

    func testCancelKeepsOldOutputStateAndPublishesCanceledSession() async {
        let bridge = OverviewRegeneratorDouble()
        let coordinator = OverviewRegenerationCoordinator()
        let model = RepositoryOverviewRegenerationModel(
            repoPath: "/tmp/repo",
            bridge: bridge,
            coordinator: coordinator,
            errorMapper: CoreBridge()
        )

        await model.load(contentLocale: "en")
        await model.prepare()
        await model.stageConfirmedPlan()
        await model.cancel()

        let cancelCalls = await bridge.cancelCallCount()
        XCTAssertEqual(cancelCalls, 1)
        XCTAssertEqual(model.sharedOperation?.session.status, .canceled)
        XCTAssertTrue(model.sharedOperation?.session.cancellationAllowed == false)
    }

    func testCoreStartupRecoveryDiscoversStagedOverviewAndPreservesReadme() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "OverviewStartupRecovery")
        defer { removeTestTemporaryItems(repoURL) }
        let readmeURL = repoURL.appendingPathComponent("README.md")
        let readmeBytes = Data("user-owned readme\n".utf8)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        try readmeBytes.write(to: readmeURL)
        let plan = try await bridge.prepareOverviewRegeneration(
            repoPath: repoURL.path,
            contentLocale: "zh-Hans"
        )
        let staged = try await bridge.startOverviewRegeneration(repoPath: repoURL.path, plan: plan)
        XCTAssertEqual(staged.status, .readyToCommit)

        _ = try await bridge.recoverOnStartup(repoPath: repoURL.path)

        let recovered = try await bridge.overviewRegeneration(
            repoPath: repoURL.path,
            operationID: plan.operationID
        )
        XCTAssertEqual(recovered.status, .completed)
        XCTAssertEqual(try Data(contentsOf: readmeURL), readmeBytes)
    }
}

private actor OverviewRegeneratorDouble: CoreOverviewRegenerating {
    private var commitCalls = 0
    private var cancelCalls = 0

    func overviewLanguageStatus(
        repoPath _: String,
        contentLocale: String
    ) async throws -> CoreOverviewLanguageStatusSnapshot {
        CoreOverviewLanguageStatusSnapshot(
            state: .needsRegeneration,
            contentLocale: contentLocale,
            targetCount: 3,
            knownTargetCount: 3,
            missingTargetCount: 0,
            obsoleteTargetCount: 0,
            knownLocales: ["en"],
            knownFormatVersions: [1],
            reasons: [.localeMismatch]
        )
    }

    func prepareOverviewRegeneration(
        repoPath _: String,
        contentLocale: String
    ) async throws -> CoreOverviewRegenerationPlanSnapshot {
        CoreOverviewRegenerationPlanSnapshot(
            operationID: "00000000-0000-4000-8000-000000000001",
            planToken: "plan-token",
            repositoryRevision: 1,
            contentLocale: contentLocale,
            formatContractVersion: 1,
            targetSetHash: String(repeating: "a", count: 64),
            targetCount: 3,
            createCount: 1,
            replaceCount: 2,
            deleteCount: 0,
            includesRootAreaMatrixFile: false,
            warnings: []
        )
    }

    func startOverviewRegeneration(
        repoPath _: String,
        plan: CoreOverviewRegenerationPlanSnapshot
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: plan.operationID, locale: plan.contentLocale, status: .readyToCommit)
    }

    func commitOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        commitCalls += 1
        return session(operationID: operationID, locale: "zh-Hans", status: .completed)
    }

    func overviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, locale: "en", status: .readyToCommit)
    }

    func recoverOverviewRegenerationOnStartup(
        repoPath _: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot? {
        nil
    }

    func resumeOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, locale: "en", status: .completed)
    }

    func cancelOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        cancelCalls += 1
        return session(operationID: operationID, locale: "en", status: .canceled)
    }

    func rollbackOverviewRegeneration(
        repoPath _: String,
        operationID: String
    ) async throws -> CoreOverviewRegenerationSessionSnapshot {
        session(operationID: operationID, locale: "en", status: .rolledBack)
    }

    func commitCallCount() -> Int {
        commitCalls
    }

    func cancelCallCount() -> Int {
        cancelCalls
    }

    private func session(
        operationID: String,
        locale: String,
        status: CoreOverviewRegenerationStatusSnapshot
    ) -> CoreOverviewRegenerationSessionSnapshot {
        CoreOverviewRegenerationSessionSnapshot(
            operationID: operationID,
            contentLocale: locale,
            repositoryRevision: 1,
            formatContractVersion: 1,
            runSequence: 1,
            status: status,
            targetCount: 3,
            stagedCount: 3,
            appliedCount: status == .completed ? 3 : 0,
            restoredCount: status == .rolledBack ? 3 : 0,
            cancellationAllowed: status == .readyToCommit,
            errorCode: nil,
            createdAt: 1,
            updatedAt: 2,
            finishedAt: [.completed, .rolledBack, .canceled].contains(status) ? 2 : nil
        )
    }
}
