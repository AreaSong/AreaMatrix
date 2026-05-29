import Foundation

extension MainFileListModel {
    func beginClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        destination: ClassifierRuleHandoffDestination
    ) {
        guard let handoff = makeClassifierRuleHandoff(
            fileID: fileID,
            targetCategory: targetCategory,
            moveFile: moveFile
        ) else {
            return
        }
        beginClassifierRuleRoute(destination.route(with: handoff), handoff: handoff)
    }

    func beginClassifierRuleSave(_ handoff: ClassifierRuleHandoff) {
        beginClassifierRuleRoute(.saveRule(handoff), handoff: handoff)
    }

    func beginClassifierImpactPreview(_ handoff: ClassifierRuleHandoff) {
        beginClassifierRuleRoute(.impactPreview(handoff), handoff: handoff)
    }

    func completeClassifierRuleSave(_ savedRule: ClassifierRuleSnapshot) {
        guard let destination = pendingActionDestination,
              destination.classifierRuleRoute != nil else { return }
        if let handoff = destination.classifierRuleRoute?.handoff, handoff.sourcePageID == "S3-04" {
            pendingActionDestination = .aiClassificationSuggestion(
                fileID: handoff.fileID,
                returnContext: AIClassificationSuggestionReturnContext(
                    appliedCategory: savedRule.targetCategory,
                    callLogID: handoff.aiProvenance?.callLogID,
                    ruleStatus: .saved
                )
            )
        } else {
            pendingActionDestination = nil
        }
        statusBanner = .savedClassifierRule(category: savedRule.targetCategory)
    }

    func cancelClassifierRuleRoute() {
        guard let route = pendingActionDestination?.classifierRuleRoute else {
            clearPendingActionDestination()
            return
        }
        let handoff = route.handoff
        if handoff.sourcePageID == "S3-04" {
            pendingActionDestination = .aiClassificationSuggestion(
                fileID: handoff.fileID,
                returnContext: AIClassificationSuggestionReturnContext(
                    appliedCategory: handoff.targetCategory,
                    callLogID: handoff.aiProvenance?.callLogID,
                    ruleStatus: .cancelled
                )
            )
            return
        }
        clearPendingActionDestination()
    }

    func beginClassifierRuleRoute(
        _ route: ClassifierCorrectionRuleRoute,
        handoff: ClassifierRuleHandoff
    ) {
        guard pendingActionDestination?.isChangeCategory(fileID: handoff.fileID) == true ||
              pendingActionDestination?.isAIClassificationSuggestion(fileID: handoff.fileID) == true,
              writeActionDisabledReason(fileID: handoff.fileID) == nil else { return }
        pendingActionDestination = .changeCategory(
            fileID: handoff.fileID,
            initialTargetCategory: handoff.targetCategory,
            mode: .classifierCorrection,
            ruleRoute: route
        )
    }

    func makeClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool
    ) -> ClassifierRuleHandoff? {
        let file = files.first { $0.id == fileID } ??
            selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
        return makeClassifierRuleHandoff(
            file: file,
            targetCategory: targetCategory,
            moveFile: moveFile,
            sourcePageID: "S2-16",
            aiProvenance: nil
        )
    }

    func makeClassifierRuleHandoff(
        file: FileEntrySnapshot?,
        targetCategory: String,
        moveFile: Bool,
        sourcePageID: String,
        aiProvenance: ClassifierRuleAIProvenance?
    ) -> ClassifierRuleHandoff? {
        guard let file,
              let draft = ClassifierRuleDraftSnapshot.classifierCorrectionDraft(
                  file: file,
                  targetCategory: targetCategory
              ) else { return nil }
        return ClassifierRuleHandoff(
            sourcePageID: sourcePageID,
            fileID: file.id,
            fileName: file.currentName,
            sourcePath: file.sourcePath ?? file.path,
            currentCategory: file.category,
            targetCategory: targetCategory,
            moveFile: moveFile,
            draft: draft,
            aiProvenance: aiProvenance
        )
    }
}

enum ClassifierImpactPreviewFilter: String, CaseIterable, Equatable, Identifiable {
    case all = "All"
    case willUpdate = "Will update"
    case needsReview = "Needs review"
    case skipped = "Skipped"

    var id: String {
        rawValue
    }
}

enum ClassifierImpactPreviewLoadState: Equatable {
    case idle
    case loading(previous: RuleImpactReportSnapshot?)
    case loaded(RuleImpactReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: RuleImpactReportSnapshot?)

    var report: RuleImpactReportSnapshot? {
        switch self {
        case let .loaded(report), let .loading(report?), let .failed(_, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

struct ClassifierImpactPreviewSheetModel: Equatable {
    var handoff: ClassifierRuleHandoff
    var moveFiles: Bool
    var filter: ClassifierImpactPreviewFilter = .all
    var loadState = ClassifierImpactPreviewLoadState.idle

    init(handoff: ClassifierRuleHandoff) {
        self.handoff = handoff
        moveFiles = handoff.moveFile
    }

    var request: ClassifierImpactPreviewRequestSnapshot {
        ClassifierImpactPreviewRequestSnapshot(
            mode: .ruleDraft,
            rule: ClassifierRuleSnapshot(
                targetCategory: handoff.targetCategory,
                keywords: selectedKeywords,
                extensions: selectedExtensions,
                priority: handoff.draft.priority,
                previewConfirmed: handoff.previewConfirmed
            ),
            moveFiles: moveFiles,
            replacementCategory: nil
        )
    }

    var selectedKeywords: [String] {
        normalizedValues(handoff.selectedKeywords, fallback: handoff.draft.keywordCandidates)
    }

    var selectedExtensions: [String] {
        normalizedExtensions(handoff.selectedExtensions, fallback: handoff.draft.extensionCandidates)
    }

    var selectedBasisSummary: String {
        let keywordSummary = selectedKeywords.isEmpty ? nil : "keyword \(selectedKeywords.joined(separator: ", "))"
        let extensionSummary = selectedExtensions.isEmpty
            ? nil
            : "extension \(selectedExtensions.joined(separator: ", "))"
        return [keywordSummary, extensionSummary].compactMap { $0 }.joined(separator: "; ")
    }

    var ruleSummary: String {
        let basis = selectedBasisSummary.isEmpty ? "selected matcher values" : selectedBasisSummary
        return "Rule: \(basis) -> \(handoff.targetCategory)"
    }

    var appliesSummary: String {
        "Applies to: future imports and existing files if applied now"
    }

    var emptyStateText: String? {
        guard loadState.report?.affectedFileCount == 0 else { return nil }
        return "This rule will only affect future imports."
    }

    var primaryApplyDisabledReason: String? {
        guard let report = loadState.report else { return "Preview must finish before apply." }
        if !report.canApply {
            return report.applyBlockedReason ?? "Resolve review items or conflicts before applying."
        }
        return nil
    }

    var filteredSamples: [RuleImpactSampleSnapshot] {
        guard let samples = loadState.report?.samples else { return [] }
        switch filter {
        case .all:
            return samples
        case .willUpdate:
            return samples.filter { $0.status == .willUpdate }
        case .needsReview:
            return samples.filter { $0.status == .needsReview || $0.status == .conflict || $0.status == .missing }
        case .skipped:
            return samples.filter { $0.status == .alreadyCorrect || $0.status == .indexOnly }
        }
    }

    mutating func markLoading() {
        loadState = .loading(previous: loadState.report)
    }

    mutating func markLoaded(_ report: RuleImpactReportSnapshot) {
        loadState = .loaded(report)
    }

    mutating func markFailed(_ mapping: CoreErrorMappingSnapshot) {
        loadState = .failed(mapping, previous: loadState.report)
    }

    mutating func setMoveFiles(_ isEnabled: Bool) {
        moveFiles = isEnabled
        loadState = .idle
    }

    private func normalizedValues(_ values: [String], fallback: [String]) -> [String] {
        let normalized = unique(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        if !normalized.isEmpty {
            return normalized
        }
        return unique(fallback.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private func normalizedExtensions(_ values: [String], fallback: [String]) -> [String] {
        normalizedValues(values.map(\.normalizedRuleExtension), fallback: fallback.map(\.normalizedRuleExtension))
    }

    private func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !value.isEmpty && !result.contains(value) {
            result.append(value)
        }
        return result
    }
}

private extension String {
    var normalizedRuleExtension: String {
        var normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasPrefix(".") {
            normalized.removeFirst()
        }
        return normalized
    }
}
