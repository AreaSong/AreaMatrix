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
    var sourcePath: String?
    var currentCategory: String
    var targetCategory: String
    var moveFile: Bool
    var draft: ClassifierRuleDraftSnapshot
    var selectedKeywords: [String] = []
    var selectedExtensions: [String] = []
    var previewConfirmed = false
}

struct ClassifierRuleHandoffSummaryRow: Equatable {
    var label: String
    var value: String
}

extension ClassifierRuleHandoff {
    var summaryRows: [ClassifierRuleHandoffSummaryRow] {
        [
            ClassifierRuleHandoffSummaryRow(label: "Source", value: sourcePageID),
            ClassifierRuleHandoffSummaryRow(label: "File", value: fileName),
            ClassifierRuleHandoffSummaryRow(label: "Current category before correction", value: currentCategory),
            ClassifierRuleHandoffSummaryRow(label: "Target category", value: targetCategory),
            ClassifierRuleHandoffSummaryRow(label: "Path", value: sourcePath ?? fileName),
            ClassifierRuleHandoffSummaryRow(label: "Move preference", value: moveFile ? "Move file" : "Metadata only"),
            ClassifierRuleHandoffSummaryRow(label: "Keyword candidates", value: keywordCandidateSummary),
            ClassifierRuleHandoffSummaryRow(label: "Extension candidates", value: extensionCandidateSummary),
            ClassifierRuleHandoffSummaryRow(label: "Priority", value: "\(draft.priority)")
        ]
    }

    private var keywordCandidateSummary: String {
        draft.keywordCandidates.isEmpty ? "None" : draft.keywordCandidates.joined(separator: ", ")
    }

    private var extensionCandidateSummary: String {
        draft.extensionCandidates.isEmpty ? "None" : draft.extensionCandidates.joined(separator: ", ")
    }
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
            priority: 0
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
              (2 ... maxLength).contains(count),
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

struct ClassifierRuleSaveSheetModel: Equatable {
    static let priorityRange: ClosedRange<Int64> = -1000 ... 1000

    var handoff: ClassifierRuleHandoff
    var selectedKeywords: [String]
    var selectedExtensions: [String]
    var priority: Int64
    var saveState = SaveState.idle

    enum SaveState: Equatable {
        case idle
        case saving
        case saved(ClassifierRuleSnapshot)
        case failed(CoreErrorMappingSnapshot)
    }

    init(handoff: ClassifierRuleHandoff) {
        self.handoff = handoff
        let keywordCandidates = Self.normalizedKeywords(handoff.draft.keywordCandidates)
        let extensionCandidates = Self.normalizedExtensions(handoff.draft.extensionCandidates)
        let hasExplicitSelection = !handoff.selectedKeywords.isEmpty ||
            !handoff.selectedExtensions.isEmpty ||
            handoff.previewConfirmed
        if hasExplicitSelection {
            selectedKeywords = Self.normalizedKeywords(handoff.selectedKeywords)
                .filter { keywordCandidates.contains($0) }
            selectedExtensions = Self.normalizedExtensions(handoff.selectedExtensions).filter {
                extensionCandidates.contains($0)
            }
        } else {
            selectedKeywords = Self.initialSelection(explicit: [], candidates: keywordCandidates)
            selectedExtensions = Self.initialSelection(explicit: [], candidates: extensionCandidates)
        }
        priority = handoff.draft.priority
    }

    var keywordCandidates: [String] {
        Self.normalizedKeywords(handoff.draft.keywordCandidates)
    }

    var extensionCandidates: [String] {
        Self.normalizedExtensions(handoff.draft.extensionCandidates)
    }

    var hasNoCandidates: Bool {
        keywordCandidates.isEmpty && extensionCandidates.isEmpty
    }

    var requiresPreviewBeforeSave: Bool {
        selectedKeywords.isEmpty && !selectedExtensions.isEmpty && !handoff.previewConfirmed
    }

    var validationMessage: String? {
        if selectedKeywords.isEmpty, selectedExtensions.isEmpty {
            return "Select at least one keyword or extension."
        }
        if !Self.priorityRange.contains(priority) {
            return "Priority must be between -1000 and 1000."
        }
        if requiresPreviewBeforeSave {
            return "Extension-only rules must be previewed before saving."
        }
        return nil
    }

    var warningMessage: String? {
        if requiresPreviewBeforeSave {
            return "This rule may affect many documents."
        }
        if !selectedExtensions.isEmpty {
            return "Extensions are saved as independent classifier matcher values."
        }
        return nil
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping) = saveState else { return nil }
        return mapping
    }

    var savedRule: ClassifierRuleSnapshot? {
        guard case let .saved(rule) = saveState else { return nil }
        return rule
    }

    var isSaving: Bool {
        if case .saving = saveState { return true }
        return false
    }

    var canSave: Bool {
        !isSaving && validationMessage == nil
    }

    var primaryActionTitle: String {
        isSaving ? "Saving..." : "Save rule"
    }

    var saveRequest: ClassifierRuleSnapshot {
        ClassifierRuleSnapshot(
            targetCategory: handoff.targetCategory,
            keywords: selectedKeywords,
            extensions: selectedExtensions,
            priority: priority,
            previewConfirmed: handoff.previewConfirmed
        )
    }

    var previewHandoff: ClassifierRuleHandoff {
        var preview = handoff
        preview.selectedKeywords = selectedKeywords
        preview.selectedExtensions = selectedExtensions
        preview.draft = ClassifierRuleDraftSnapshot(
            sourceFileID: handoff.draft.sourceFileID,
            targetCategory: handoff.targetCategory,
            keywordCandidates: selectedKeywords,
            extensionCandidates: selectedExtensions,
            priority: priority
        )
        return preview
    }

    var rulePreviewLines: [String] {
        var lines = selectedKeywords.map { "Append keyword \"\($0)\" to \(handoff.targetCategory).keywords" }
        lines += selectedExtensions.map { "Append extension \"\($0)\" to \(handoff.targetCategory).extensions" }
        lines.append("Use priority \(priority) for \(handoff.targetCategory)")
        return lines
    }

    mutating func setKeyword(_ keyword: String, isSelected: Bool) {
        selectedKeywords = Self.updatedSelection(selectedKeywords, value: keyword, isSelected: isSelected)
        saveState = .idle
    }

    mutating func setExtension(_ ext: String, isSelected: Bool) {
        selectedExtensions = Self.updatedSelection(selectedExtensions, value: ext, isSelected: isSelected)
        saveState = .idle
    }

    mutating func markSaving() {
        saveState = .saving
    }

    mutating func markSaved(_ rule: ClassifierRuleSnapshot) {
        saveState = .saved(rule)
    }

    mutating func markFailed(_ mapping: CoreErrorMappingSnapshot) {
        saveState = .failed(mapping)
    }

    private static func initialSelection(explicit: [String], candidates: [String]) -> [String] {
        let normalizedExplicit = explicit.filter { candidates.contains($0) }
        if !normalizedExplicit.isEmpty {
            return normalizedExplicit
        }
        return Array(candidates.prefix(1))
    }

    private static func updatedSelection(_ values: [String], value: String, isSelected: Bool) -> [String] {
        if isSelected {
            return values.contains(value) ? values : values + [value]
        }
        return values.filter { $0 != value }
    }

    private static func normalizedKeywords(_ values: [String]) -> [String] {
        unique(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private static func normalizedExtensions(_ values: [String]) -> [String] {
        unique(values.map {
            normalizedExtension($0)
        })
    }

    private static func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !value.isEmpty && !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func normalizedExtension(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while normalized.hasPrefix(".") {
            normalized.removeFirst()
        }
        return normalized
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
