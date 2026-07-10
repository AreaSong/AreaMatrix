@testable import AreaMatrix
import XCTest

enum RemotePrivacyRulesRequestPosition {
    case first
    case last
}

actor RemotePrivacyRulesBridge: CoreAIPrivacyRulesManaging, CoreAIPrivacyEvaluating {
    struct Requests: Equatable {
        var loadCount = 0
        var updates: [AiPrivacyRulesUpdateRequest] = []
        var evaluations: [AiPrivacyEvaluationRequest] = []
    }

    private var snapshot: AiPrivacyRulesSnapshot
    private let evaluationReport: AiPrivacyEvaluationReport
    private let updateFails: Bool
    private var recorded = Requests()

    init(
        snapshot: AiPrivacyRulesSnapshot = .remoteProviderConfigPrivacyRules(),
        evaluationReport: AiPrivacyEvaluationReport = .remoteProviderConfigAllowedPrivacyEvaluation(),
        updateFails: Bool = false
    ) {
        self.snapshot = snapshot
        self.evaluationReport = evaluationReport
        self.updateFails = updateFails
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        recorded.loadCount += 1
        return snapshot
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        recorded.updates.append(request)
        if updateFails {
            throw CoreError.Db(message: "privacy gate write failed")
        }
        snapshot = snapshot.applyingPrivacyGateRequest(request)
        return snapshot
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recorded.evaluations.append(request)
        return evaluationReport
    }

    func assertLoadCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.loadCount, expectedCount, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded, Requests(), file: file, line: line)
    }

    func assertUpdateCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.updates.count, expectedCount, file: file, line: line)
    }

    func assertUpdate(
        at index: Int,
        privacyGateEnabled expectedPrivacyGateEnabled: Bool,
        confirmed expectedConfirmed: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = update(at: index, file: file, line: line) else { return }

        XCTAssertEqual(request.privacyGateEnabled, expectedPrivacyGateEnabled, file: file, line: line)
        if let expectedConfirmed {
            XCTAssertEqual(request.confirmed, expectedConfirmed, file: file, line: line)
        }
    }

    func assertProviderScope(
        at index: Int,
        providerConfigured expectedProviderConfigured: Bool? = nil,
        remoteProviderEnabled expectedRemoteProviderEnabled: Bool? = nil,
        featureScope expectedFeatureScope: [AiFeatureKind]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let providerScope = update(at: index, file: file, line: line)?.providerScope else { return }

        if let expectedProviderConfigured {
            XCTAssertEqual(providerScope.providerConfigured, expectedProviderConfigured, file: file, line: line)
        }
        if let expectedRemoteProviderEnabled {
            XCTAssertEqual(providerScope.remoteProviderEnabled, expectedRemoteProviderEnabled, file: file, line: line)
        }
        if let expectedFeatureScope {
            XCTAssertEqual(providerScope.featureScope, expectedFeatureScope, file: file, line: line)
        }
    }

    func assertUpdateRule(
        at index: Int,
        position: RemotePrivacyRulesRequestPosition,
        name expectedName: String? = nil,
        pattern expectedPattern: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rules = update(at: index, file: file, line: line)?.rules else { return }
        let rule = switch position {
        case .first:
            rules.first
        case .last:
            rules.last
        }

        if let expectedName {
            XCTAssertEqual(rule?.name, expectedName, file: file, line: line)
        }
        if let expectedPattern {
            XCTAssertEqual(rule?.pattern, expectedPattern, file: file, line: line)
        }
    }

    func assertUpdateFieldPolicy(
        at index: Int,
        field expectedField: AiPrivacyInputField,
        allowRemote expectedAllowRemote: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = update(at: index, file: file, line: line) else { return }

        XCTAssertEqual(
            request.remoteAllowedFields.first { $0.field == expectedField }?.allowRemote,
            expectedAllowRemote,
            file: file,
            line: line
        )
    }

    func assertUpdateFieldPolicy(
        at index: Int,
        fieldIndex expectedFieldIndex: Int,
        field expectedField: AiPrivacyInputField,
        allowRemote expectedAllowRemote: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = update(at: index, file: file, line: line) else { return }

        XCTAssertEqual(
            request.remoteAllowedFields[safe: expectedFieldIndex]?.field,
            expectedField,
            file: file,
            line: line
        )
        XCTAssertEqual(
            request.remoteAllowedFields[safe: expectedFieldIndex]?.allowRemote,
            expectedAllowRemote,
            file: file,
            line: line
        )
    }

    func assertNoEvaluations(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.evaluations, [], file: file, line: line)
    }

    func assertEvaluationCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.evaluations.count, expectedCount, file: file, line: line)
    }

    func assertEvaluationFeatures(
        _ expectedFeatures: [AiFeatureKind],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.evaluations.map(\.feature), expectedFeatures, file: file, line: line)
    }

    func assertEvaluation(
        at index: Int,
        feature expectedFeature: AiFeatureKind? = nil,
        route expectedRoute: AiPrivacyEvaluationRoute? = nil,
        repoRelativePath expectedRepoRelativePath: String? = nil,
        fileName expectedFileName: String? = nil,
        category expectedCategory: String? = nil,
        fileExtension expectedExtension: String? = nil,
        tags expectedTags: [String]? = nil,
        requestedFields expectedRequestedFields: [AiPrivacyInputField]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = evaluation(at: index, file: file, line: line) else { return }

        if let expectedFeature {
            XCTAssertEqual(request.feature, expectedFeature, file: file, line: line)
        }
        if let expectedRoute {
            XCTAssertEqual(request.route, expectedRoute, file: file, line: line)
        }
        if let expectedRepoRelativePath {
            XCTAssertEqual(request.context.repoRelativePath, expectedRepoRelativePath, file: file, line: line)
        }
        if let expectedFileName {
            XCTAssertEqual(request.context.fileName, expectedFileName, file: file, line: line)
        }
        if let expectedCategory {
            XCTAssertEqual(request.context.category, expectedCategory, file: file, line: line)
        }
        if let expectedExtension {
            XCTAssertEqual(request.context.extension, expectedExtension, file: file, line: line)
        }
        if let expectedTags {
            XCTAssertEqual(request.context.tags, expectedTags, file: file, line: line)
        }
        if let expectedRequestedFields {
            XCTAssertEqual(request.requestedFields, expectedRequestedFields, file: file, line: line)
        }
    }

    private func update(
        at index: Int,
        file: StaticString,
        line: UInt
    ) -> AiPrivacyRulesUpdateRequest? {
        guard recorded.updates.indices.contains(index) else {
            XCTFail("Expected AI privacy update request at index \(index).", file: file, line: line)
            return nil
        }

        return recorded.updates[index]
    }

    private func evaluation(
        at index: Int,
        file: StaticString,
        line: UInt
    ) -> AiPrivacyEvaluationRequest? {
        guard recorded.evaluations.indices.contains(index) else {
            XCTFail("Expected AI privacy evaluation request at index \(index).", file: file, line: line)
            return nil
        }

        return recorded.evaluations[index]
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

actor AIPrivacyRulesFailingBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules read failed")
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request _: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules write failed")
    }
}
