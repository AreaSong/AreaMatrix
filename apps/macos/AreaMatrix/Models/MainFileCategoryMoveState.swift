import Foundation

struct MainFileCategoryMovePreviewRequest: Equatable {
    var fileID: Int64
    var targetCategory: String
}

enum MainFileCategoryMoveFailureOperation: Equatable {
    case preview
    case move
    case correction
}

enum MainFileCategoryMoveMode: Equatable {
    case moveToCategory
    case classifierCorrection
}

enum ClassifierCorrectionRuleRoute: Equatable {
    case saveRule(ClassifierRuleHandoff)
    case impactPreview(ClassifierRuleHandoff)

    var pageID: String {
        switch self {
        case .saveRule: "S2-17"
        case .impactPreview: "S2-18"
        }
    }

    var handoff: ClassifierRuleHandoff {
        switch self {
        case let .saveRule(handoff), let .impactPreview(handoff):
            handoff
        }
    }

}

enum ClassifierRuleHandoffDestination: Equatable {
    case saveRule
    case impactPreview

    func route(with handoff: ClassifierRuleHandoff) -> ClassifierCorrectionRuleRoute {
        switch self {
        case .saveRule:
            .saveRule(handoff)
        case .impactPreview:
            .impactPreview(handoff)
        }
    }
}

struct MainFileCategoryMoveOptions: Equatable {
    var moveFile: Bool
    var remember: Bool
}

struct ClassifierRuleHandoff: Equatable {
    var sourcePageID: String
    var fileID: Int64
    var fileName: String
    var currentCategory: String
    var targetCategory: String
    var moveFile: Bool
    var draft: ClassifierRuleDraftSnapshot
}

extension ClassifierRuleDraftSnapshot {
    static func classifierCorrectionDraft(
        file: FileEntrySnapshot,
        targetCategory: String
    ) -> ClassifierRuleDraftSnapshot? {
        let keywordCandidates = ruleKeywordCandidates(file: file)
        let extensionCandidates = ruleExtensionCandidates(file: file)
        guard !keywordCandidates.isEmpty || !extensionCandidates.isEmpty else { return nil }

        return ClassifierRuleDraftSnapshot(
            sourceFileID: file.id,
            targetCategory: targetCategory,
            keywordCandidates: keywordCandidates,
            extensionCandidates: extensionCandidates,
            priority: 100
        )
    }

    private static func ruleKeywordCandidates(file: FileEntrySnapshot) -> [String] {
        var candidates: [String] = []
        collectRuleKeywords(from: file.currentName, into: &candidates)
        collectRuleKeywords(from: file.path, into: &candidates)
        return candidates
    }

    private static func collectRuleKeywords(from path: String, into candidates: inout [String]) {
        for component in path.split(separator: "/") {
            let stem = String(component).deletingPathExtension
            for token in stem.split(whereSeparator: isRuleTokenSeparator) {
                pushRuleCandidate(String(token).lowercased(), into: &candidates, maxLength: 32)
            }
        }
    }

    private static func ruleExtensionCandidates(file: FileEntrySnapshot) -> [String] {
        var candidates: [String] = []
        for path in [file.currentName, file.path] {
            pushRuleCandidate(path.pathExtension.lowercased(), into: &candidates, maxLength: 16)
        }
        return candidates
    }

    private static func pushRuleCandidate(
        _ candidate: String,
        into candidates: inout [String],
        maxLength: Int
    ) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        guard candidates.count < 5,
              (2...maxLength).contains(count),
              !trimmed.contains(where: isUnsafeRuleCandidateCharacter),
              !candidates.contains(trimmed) else { return }
        candidates.append(trimmed)
    }

    private static func isRuleTokenSeparator(_ character: Character) -> Bool {
        character == " " || character == "_" || character == "-" || character == "." ||
            character == "\t" || character == "/" || character == "\\" ||
            character == "(" || character == ")" || character == "[" || character == "]"
    }

    private static func isUnsafeRuleCandidateCharacter(_ character: Character) -> Bool {
        character == "/" || character == "\\" || character == ":" || character == "\0"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    var pathExtension: String {
        (self as NSString).pathExtension
    }
}

struct ClassifierCorrectionContextRequest: Equatable {
    var fileID: Int64
    var filename: String
}

enum ClassifierCorrectionContextState: Equatable {
    case idle
    case loading(ClassifierCorrectionContextRequest)
    case loaded(ClassifierCorrectionContextRequest, ClassifyResultSnapshot)
    case failed(ClassifierCorrectionContextRequest, CoreErrorMappingSnapshot)

    func needsLoad(_ request: ClassifierCorrectionContextRequest) -> Bool {
        switch self {
        case .idle:
            true
        case let .loading(current), let .loaded(current, _), let .failed(current, _):
            current != request
        }
    }

    func isLoading(_ request: ClassifierCorrectionContextRequest) -> Bool {
        guard case let .loading(current) = self else { return false }
        return current == request
    }

    func result(for fileID: Int64) -> ClassifyResultSnapshot? {
        guard case let .loaded(request, result) = self, request.fileID == fileID else { return nil }
        return result
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case let .failed(request, mapping) = self, request.fileID == fileID else { return nil }
        return mapping
    }
}

enum MainFileCategoryMoveState: Equatable {
    case idle
    case checking(MainFileCategoryMovePreviewRequest)
    case ready(MainFileCategoryMovePreviewRequest, MoveToCategoryPreviewSnapshot)
    case moving(MainFileCategoryMovePreviewRequest, preview: MoveToCategoryPreviewSnapshot?)
    case failed(
        MainFileCategoryMovePreviewRequest,
        operation: MainFileCategoryMoveFailureOperation,
        CoreErrorMappingSnapshot
    )

    func isChecking(_ request: MainFileCategoryMovePreviewRequest) -> Bool {
        guard case let .checking(currentRequest) = self else { return false }
        return currentRequest == request
    }

    func isChecking(fileID: Int64, targetCategory: String) -> Bool {
        isChecking(MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory))
    }

    func isMoving(fileID: Int64) -> Bool {
        guard case let .moving(request, _) = self else { return false }
        return request.fileID == fileID
    }

    func preview(for request: MainFileCategoryMovePreviewRequest) -> MoveToCategoryPreviewSnapshot? {
        switch self {
        case let .ready(currentRequest, preview) where currentRequest == request:
            preview
        case let .moving(currentRequest, preview) where currentRequest == request:
            preview
        default:
            nil
        }
    }

    func failure(for fileID: Int64, targetCategory: String) -> CoreErrorMappingSnapshot? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case let .failed(currentRequest, _, mapping) = self,
              currentRequest == request else { return nil }
        return mapping
    }

    func failureOperation(
        for fileID: Int64,
        targetCategory: String
    ) -> MainFileCategoryMoveFailureOperation? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case let .failed(currentRequest, operation, _) = self,
              currentRequest == request else { return nil }
        return operation
    }

    func unresolvedNameConflict(
        for fileID: Int64,
        targetCategory: String
    ) -> CoreErrorMappingSnapshot? {
        guard failureOperation(for: fileID, targetCategory: targetCategory) == .preview,
              let mapping = failure(for: fileID, targetCategory: targetCategory),
              mapping.kind == .conflict else { return nil }
        return mapping
    }
}
