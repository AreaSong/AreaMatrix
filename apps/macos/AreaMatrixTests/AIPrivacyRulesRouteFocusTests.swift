@testable import AreaMatrix
import XCTest

final class AIPrivacyRulesRouteFocusTests: XCTestCase {
    func testAIPrivacyRulesRouteFocusTargetsRuleAndFieldRowsForOneShotHighlight() {
        let ruleFocus = AIPrivacyRulesRouteFocus.rule(ruleID: " rule-confidential ")
        XCTAssertEqual(ruleFocus.targetID, "aiPrivacyRules-rule-rule-confidential")
        XCTAssertEqual(ruleFocus.label, L10n.format("ai.privacy.focusedRule", "rule-confidential"))
        XCTAssertTrue(ruleFocus.matches(ruleID: "rule-confidential"))
        XCTAssertFalse(ruleFocus.matches(ruleID: "rule-other"))

        let fieldFocus = AIPrivacyRulesRouteFocus.field(.noteSummary)
        XCTAssertEqual(fieldFocus.targetID, "aiPrivacyRules-field-noteSummary")
        XCTAssertEqual(fieldFocus.label, L10n.format("ai.privacy.focusedField", aiPrivacyInputFieldLabel(.noteSummary)))
        XCTAssertTrue(fieldFocus.matches(field: .noteSummary))
        XCTAssertFalse(fieldFocus.matches(field: .fileName))
    }

    @MainActor
    func testAICategorySuggestionPrivacySkippedActionBuildsAIPrivacyRulesRuleFocusedRoute() {
        let model = aiCategorySuggestionSuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 309, contextPolicy: .fileNameAndPath),
            bridge: AICategorySuggestionSuggestionBridge(result: .success(.aiCategorySuggestionSuggested(fileID: 309)))
        )
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "confidential.pdf",
            currentPath: "inbox/confidential.pdf"
        )

        let route = panel.aiPrivacyRulesPrivacyRuleRoute(ruleID: " rule-confidential ")

        XCTAssertEqual(route?.repoPath, "/tmp/repo")
        XCTAssertEqual(route?.focus, .rule(ruleID: "rule-confidential"))
        XCTAssertEqual(route?.focus?.targetID, "aiPrivacyRules-rule-rule-confidential")
    }

    @MainActor
    func testAISummaryPrivacySkippedNoticeBuildsAIPrivacyRulesRuleAndFieldFocusedRoutes() {
        let ruleNotice = AISummaryEditorNotice(
            title: "Skipped by privacy rule",
            detail: "A privacy rule blocked the summary input.",
            recovery: "Review privacy rules before generating this summary.",
            capability: "ai-privacy-rules-core",
            opensAISettings: false,
            privacyRuleID: " rule-summary ",
            privacyField: nil,
            reason: .privacyBlocked(AISummaryPrivacySkip(summaryReason: .privacyRule))
        )
        let fieldNotice = AISummaryEditorNotice(
            title: "No eligible summary input",
            detail: "All remote summary fields are blocked.",
            recovery: "Review privacy rules before generating this summary.",
            capability: "ai-privacy-rules-core",
            opensAISettings: false,
            privacyRuleID: nil,
            privacyField: .noteSummary,
            reason: .noEligibleInput(AISummaryPrivacySkip(summaryReason: .noEligibleInput))
        )

        let ruleRoute = ruleNotice.aiPrivacyRulesPrivacyRulesRoute(repoPath: "/tmp/aiPrivacyRules")
        let fieldRoute = fieldNotice.aiPrivacyRulesPrivacyRulesRoute(repoPath: "/tmp/aiPrivacyRules")

        XCTAssertEqual(ruleRoute?.repoPath, "/tmp/aiPrivacyRules")
        XCTAssertEqual(ruleRoute?.focus, .rule(ruleID: "rule-summary"))
        XCTAssertEqual(ruleRoute?.focus?.targetID, "aiPrivacyRules-rule-rule-summary")
        XCTAssertEqual(ruleNotice.aiPrivacyRulesRouteAccessibilitySuffix, "privacy-rule-rule-summary")
        XCTAssertEqual(fieldRoute?.repoPath, "/tmp/aiPrivacyRules")
        XCTAssertEqual(fieldRoute?.focus, .field(.noteSummary))
        XCTAssertEqual(fieldRoute?.focus?.targetID, "aiPrivacyRules-field-noteSummary")
        XCTAssertEqual(fieldNotice.aiPrivacyRulesRouteAccessibilitySuffix, "privacy-field-noteSummary")
    }
}
