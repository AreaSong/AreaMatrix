import Combine
import Foundation

enum MainDetailNoteSaveStatus: Equatable {
    case saved
    case unsaved
    case saving
    case failed(CoreErrorMappingSnapshot)

    var title: String {
        switch self {
        case .saved:
            "Saved"
        case .unsaved:
            "Unsaved"
        case .saving:
            "Saving..."
        case .failed:
            "Unsaved"
        }
    }

    var failedError: CoreErrorMappingSnapshot? {
        if case let .failed(error) = self { return error }
        return nil
    }
}

enum MainDetailNoteWriteBlock: Equatable {
    case repoReadOnly
    case fileMissing
    case importLocked
    case listLoading

    var message: String {
        switch self {
        case .repoReadOnly:
            "Repository is read-only. Note editing is disabled."
        case .fileMissing:
            "文件缺失时暂不能保存笔记"
        case .importLocked:
            "This file is locked by an import. Note editing is disabled."
        case .listLoading:
            "Current list is loading. Note editing is temporarily disabled."
        }
    }
}

struct AITagBatchSuggestionReview: Equatable {
    var files: [FileEntrySnapshot]
    var reports: [Int64: AiTagSuggestionReport]
    var selectedIDsByFileID: [Int64: Set<String>]
    var loadFailures: [Int64: CoreErrorMappingSnapshot]
    var applyReports: [Int64: AiTagSuggestionApplyReport] = [:]
    var applyFailures: [Int64: CoreErrorMappingSnapshot] = [:]
    var editSessionsByFileID: [Int64: AITagSuggestionEditSession] = [:]
    var rejectedFeedback: [AITagSuggestionRejectedFeedback] = []

    var selectedFileCount: Int {
        selectedIDsByFileID.filter { !$0.value.isEmpty }.count
    }

    var selectedTagCount: Int {
        selectedIDsByFileID.values.reduce(0) { $0 + $1.count }
    }

    var lowConfidenceExcludedCount: Int {
        reports.values.reduce(0) { count, report in
            count + report.suggestions.filter {
                AITagSuggestionAction.canApply($0) &&
                    $0.confidence < report.confidenceThreshold &&
                    selectedIDsByFileID[report.fileId]?.contains($0.suggestionId) != true
            }.count
        }
    }

    var duplicateCount: Int {
        reports.values.reduce(0) { count, report in
            count + report.suggestions.filter { $0.status == .alreadyApplied }.count
        }
    }

    var invalidCount: Int {
        let selectedInvalidCount = reports.values.reduce(0) { count, report in
            if editSessionsByFileID[report.fileId] != nil { return count }
            let selectedIDs = selectedIDsByFileID[report.fileId] ?? []
            return count + report.suggestions.filter { suggestion in
                selectedIDs.contains(suggestion.suggestionId) &&
                    (suggestion.status == .invalid || suggestion.status == .blocked)
            }.count
        }
        return selectedInvalidCount + editSessionsByFileID.values.reduce(0) { $0 + $1.attentionCount }
    }

    var appliedFileCount: Int {
        applyReports.values.filter { $0.appliedCount > 0 || $0.skippedCount > 0 }.count
    }

    var failedFileCount: Int {
        applyFailures.count + applyReports.values.filter { $0.failedCount > 0 }.count
    }

    var appliedTagCount: Int64 {
        applyReports.values.reduce(Int64(0)) { $0 + $1.appliedCount }
    }

    var failedTagCount: Int64 {
        applyReports.values.reduce(Int64(applyFailures.count)) { $0 + $1.failedCount }
    }

    var canApply: Bool {
        selectedTagCount > 0 && invalidCount == 0
    }

    func applyItems(fileID: Int64) -> [ApplyAiTagSuggestionItem] {
        if let session = editSessionsByFileID[fileID] { return session.applyItems }
        guard let report = reports[fileID], let selected = selectedIDsByFileID[fileID] else { return [] }
        return report.suggestions.compactMap { suggestion in
            guard selected.contains(suggestion.suggestionId), AITagSuggestionAction.canApply(suggestion) else {
                return nil
            }
            return ApplyAiTagSuggestionItem(suggestion: suggestion, editedByUser: false)
        }
    }
}

enum AITagBatchSuggestionState: Equatable {
    case idle
    case loading(AITagBatchSuggestionReview)
    case reviewing(AITagBatchSuggestionReview)
    case confirming(AITagBatchSuggestionReview)
    case applying(AITagBatchSuggestionReview)
    case applied(AITagBatchSuggestionReview)

    var review: AITagBatchSuggestionReview? {
        switch self {
        case let .loading(review), let .reviewing(review), let .confirming(review),
             let .applying(review), let .applied(review):
            review
        case .idle:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }

    var isConfirming: Bool {
        if case .confirming = self { return true }
        return false
    }

    var canApplySelectedSuggestions: Bool {
        review?.canApply == true && !isLoading && !isApplying
    }

    var hasHighConfidenceApplyCandidates: Bool {
        guard let review else { return false }
        return review.reports.values.contains { report in
            report.suggestions.contains {
                AITagSuggestionAction.canApply($0) && $0.confidence >= report.confidenceThreshold
            }
        }
    }

    var fileIDs: Set<Int64> {
        Set(review?.files.map(\.id) ?? [])
    }
}

struct AITagBatchSuggestionActions {
    let load: ([FileEntrySnapshot]) -> Void
    let retry: () -> Void
    let toggle: (Int64, String) -> Void
    let startEditing: (Int64, String) -> Void
    let cancelEditing: (Int64) -> Void
    let editDisplayName: (Int64, String, String) -> Void
    let editSlug: (Int64, String, String) -> Void
    let regenerateSlug: (Int64, String) -> Void
    let selectHighConfidence: () -> Void
    let clearSelection: () -> Void
    let confirm: () -> Void
    let cancelConfirmation: () -> Void
    let apply: () -> Void
    let cancel: () -> Void
}

extension AITagBatchSuggestionActions {
    static var noop: AITagBatchSuggestionActions {
        AITagBatchSuggestionActions(
            load: { _ in }, retry: {}, toggle: { _, _ in },
            startEditing: { _, _ in }, cancelEditing: { _ in },
            editDisplayName: { _, _, _ in }, editSlug: { _, _, _ in },
            regenerateSlug: { _, _ in },
            selectHighConfidence: {}, clearSelection: {}, confirm: {},
            cancelConfirmation: {}, apply: {}, cancel: {}
        )
    }
}

enum MainDetailNoteState: Equatable {
    case notLoaded
    case loading(fileID: Int64)
    case empty(fileID: Int64, writeBlock: MainDetailNoteWriteBlock?)
    case editing(
        fileID: Int64,
        content: String,
        saveStatus: MainDetailNoteSaveStatus,
        writeBlock: MainDetailNoteWriteBlock?
    )
    case failed(fileID: Int64, CoreErrorMappingSnapshot, writeBlock: MainDetailNoteWriteBlock?)

    var content: String {
        if case let .editing(_, content, _, _) = self { return content }
        return ""
    }

    var saveStatus: MainDetailNoteSaveStatus? {
        if case let .editing(_, _, saveStatus, _) = self { return saveStatus }
        return nil
    }

    var writeBlock: MainDetailNoteWriteBlock? {
        switch self {
        case let .empty(_, block), let .editing(_, _, _, block), let .failed(_, _, block):
            block
        case .notLoaded, .loading:
            nil
        }
    }
}

@MainActor
final class DetailNoteModel: ObservableObject {
    @Published private(set) var state: MainDetailNoteState = .notLoaded
    @Published private var isEditorFocusRequested = false

    private let repoPath: String
    private let noteStore: any CoreNoteReadingWriting
    private let errorMapper: any CoreErrorMapping
    private let inFlightTracker: any InFlightFileChangeTracking
    private let debounceNanoseconds: UInt64
    private var currentFile: FileEntrySnapshot?
    private var currentWriteBlock: MainDetailNoteWriteBlock?
    private var loadGeneration = 0
    private var pendingSaveTask: Task<Void, Never>?
    private var cachedDrafts: [Int64: DetailNoteCachedDraft] = [:]

    init(
        repoPath: String,
        noteStore: any CoreNoteReadingWriting,
        errorMapper: any CoreErrorMapping,
        inFlightTracker: any InFlightFileChangeTracking = InFlightFileChangeTracker.shared,
        debounceNanoseconds: UInt64 = 800_000_000
    ) {
        self.repoPath = repoPath
        self.noteStore = noteStore
        self.errorMapper = errorMapper
        self.inFlightTracker = inFlightTracker
        self.debounceNanoseconds = debounceNanoseconds
    }

    var noteText: String {
        state.content
    }

    var canOpenNoteFile: Bool {
        guard case .editing(_, _, .saved, _) = state else { return false }
        return true
    }

    var editorFocusRequest: Bool {
        isEditorFocusRequested
    }

    var noteSidecarRelativePath: String? {
        currentFile.map(Self.sidecarRelativePath)
    }

    func failedDraftFileIDLeaving(fileID: Int64?) -> Int64? {
        guard let fileID, cachedDrafts[fileID]?.isFailed == true else { return nil }
        return fileID
    }

    func load(file: FileEntrySnapshot, writeBlock: MainDetailNoteWriteBlock?) async {
        if currentFile?.id == file.id, !stateNeedsReload {
            currentFile = file
            updateWriteBlock(writeBlock)
            return
        }

        pendingSaveTask?.cancel()
        currentFile = file
        currentWriteBlock = writeBlock
        loadGeneration += 1
        let generation = loadGeneration

        if let draft = cachedDrafts[file.id] {
            state = .editing(
                fileID: file.id,
                content: draft.content,
                saveStatus: draft.saveStatus,
                writeBlock: writeBlock
            )
            return
        }

        state = .loading(fileID: file.id)
        do {
            let note = try await noteStore.readNote(repoPath: repoPath, fileID: file.id)
            guard generation == loadGeneration, currentFile?.id == file.id else { return }
            if let note {
                state = .editing(fileID: file.id, content: note, saveStatus: .saved, writeBlock: writeBlock)
            } else {
                state = .empty(fileID: file.id, writeBlock: writeBlock)
            }
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == loadGeneration, currentFile?.id == file.id else { return }
            state = .failed(fileID: file.id, mappedError, writeBlock: writeBlock)
        }
    }

    func retryLoad() async {
        guard let currentFile else { return }
        let writeBlock = currentWriteBlock
        state = .notLoaded
        await load(file: currentFile, writeBlock: writeBlock)
    }

    func updateWriteBlock(_ writeBlock: MainDetailNoteWriteBlock?) {
        currentWriteBlock = writeBlock
        switch state {
        case let .empty(fileID, _):
            state = .empty(fileID: fileID, writeBlock: writeBlock)
        case let .editing(fileID, content, saveStatus, _):
            state = .editing(fileID: fileID, content: content, saveStatus: saveStatus, writeBlock: writeBlock)
        case let .failed(fileID, error, _):
            state = .failed(fileID: fileID, error, writeBlock: writeBlock)
        case .notLoaded, .loading:
            break
        }
    }

    func createNote() {
        guard let currentFile, currentWriteBlock == nil else { return }
        state = .editing(fileID: currentFile.id, content: "", saveStatus: .unsaved, writeBlock: nil)
        cachedDrafts[currentFile.id] = DetailNoteCachedDraft(content: "", saveStatus: .unsaved)
        requestEditorFocus()
    }

    func consumeEditorFocusRequest() {
        isEditorFocusRequested = false
    }

    func updateDraft(_ content: String) {
        guard let currentFile, currentWriteBlock == nil else { return }
        guard case let .editing(fileID, previousContent, _, _) = state, fileID == currentFile.id else { return }
        guard content != previousContent else { return }

        state = .editing(fileID: fileID, content: content, saveStatus: .unsaved, writeBlock: nil)
        cachedDrafts[fileID] = DetailNoteCachedDraft(content: content, saveStatus: .unsaved)
        scheduleSave(file: currentFile, content: content)
    }

    func retrySave() async {
        guard let currentFile, currentWriteBlock == nil else { return }
        guard case let .editing(fileID, content, .failed, _) = state, fileID == currentFile.id else { return }
        await save(file: currentFile, content: content)
    }

    private var stateNeedsReload: Bool {
        if case .notLoaded = state { return true }
        return false
    }

    private func scheduleSave(file: FileEntrySnapshot, content: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 800_000_000)
            } catch {
                return
            }
            await self?.save(file: file, content: content)
        }
    }

    private func save(file: FileEntrySnapshot, content: String) async {
        guard currentWriteBlock == nil else { return }
        let notePath = Self.sidecarRelativePath(for: file)
        if currentFile?.id == file.id {
            state = .editing(fileID: file.id, content: content, saveStatus: .saving, writeBlock: nil)
        }
        await inFlightTracker.mark(repoPath: repoPath, relativePath: notePath)

        do {
            try await noteStore.writeNote(repoPath: repoPath, fileID: file.id, contentMarkdown: content)
            await inFlightTracker.unmark(repoPath: repoPath, relativePath: notePath)
            cachedDrafts[file.id] = nil
            guard currentFile?.id == file.id else { return }
            state = .editing(fileID: file.id, content: content, saveStatus: .saved, writeBlock: nil)
        } catch {
            await inFlightTracker.unmark(repoPath: repoPath, relativePath: notePath)
            let mappedError = await mapCoreError(error)
            cachedDrafts[file.id] = DetailNoteCachedDraft(content: content, saveStatus: .failed(mappedError))
            guard currentFile?.id == file.id else { return }
            state = .editing(fileID: file.id, content: content, saveStatus: .failed(mappedError), writeBlock: nil)
        }
    }

    private func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func requestEditorFocus() {
        isEditorFocusRequested = false
        isEditorFocusRequested = true
    }

    private static func sidecarRelativePath(for file: FileEntrySnapshot) -> String {
        "\(file.path).md"
    }
}

private struct DetailNoteCachedDraft {
    var content: String
    var saveStatus: MainDetailNoteSaveStatus

    var isFailed: Bool {
        saveStatus.failedError != nil
    }
}
