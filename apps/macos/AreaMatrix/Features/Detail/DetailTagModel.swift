import AreaMatrixFeatureLibrary
import Combine
import Foundation

@MainActor
final class DetailTagModel: ObservableObject {
    struct Context {
        var selectedFileID: () -> Int64?
        var selectedFile: (Int64) -> FileEntrySnapshot?
        var writeDisabledMessage: (String) -> String?
        var writableFileID: (Int64?) -> Int64?
        var loadChangeLog: (Int64) async -> Void
        var requestDetailTab: (DetailPaneTab) -> Void
    }

    @Published var filterRegistryState = TagFilterRegistryState.idle
    @Published var editorState = DetailTagEditorState.notLoaded
    @Published var suggestionState = DetailTagSuggestionState.idle
    @Published var aiSuggestionState = AITagSuggestionState.idle
    @Published var presentationRequest: TagSuggestionPresentationRequest?
    @Published var undoToast: DetailTagUndoToast?

    let repoPath: String
    let tagStore: any CoreTagCRUD
    let errorMapper: any CoreErrorMapping
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let undoActionStore: any CoreUndoActionLogging
    var filterRegistryGeneration = 0
    var presentationSequence = 0

    private var selectedFileID: () -> Int64? = { nil }
    private var selectedFile: (Int64) -> FileEntrySnapshot? = { _ in nil }
    private var writeDisabledMessage: (String) -> String? = { message in message }
    private var writableFileID: (Int64?) -> Int64? = { _ in nil }
    private var loadChangeLog: (Int64) async -> Void = { _ in }
    private var requestDetailTab: (DetailPaneTab) -> Void = { _ in }

    init(
        repoPath: String,
        tagStore: any CoreTagCRUD,
        aiSettingsLoader: any CoreAISettingsLoading,
        aiTagSuggestionStore: any CoreAITagSuggestionManaging,
        aiPrivacyRules: any CoreAIPrivacyEvaluating,
        undoActionStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.tagStore = tagStore
        self.aiSettingsLoader = aiSettingsLoader
        self.aiTagSuggestionStore = aiTagSuggestionStore
        self.aiPrivacyRules = aiPrivacyRules
        self.undoActionStore = undoActionStore
        self.errorMapper = errorMapper
    }

    func setContext(_ context: Context) {
        selectedFileID = context.selectedFileID
        selectedFile = context.selectedFile
        writeDisabledMessage = context.writeDisabledMessage
        writableFileID = context.writableFileID
        loadChangeLog = context.loadChangeLog
        requestDetailTab = context.requestDetailTab
    }

    var currentSelectedFileID: Int64? {
        selectedFileID()
    }

    func currentSelectedFile(_ fileID: Int64) -> FileEntrySnapshot? {
        selectedFile(fileID)
    }

    func selectedWriteActionDisabledMessage(noSelectionMessage: String) -> String? {
        writeDisabledMessage(noSelectionMessage)
    }

    func writableActionFileID(_ fileID: Int64? = nil) -> Int64? {
        writableFileID(fileID)
    }

    func refreshChangeLog(fileID: Int64) async {
        await loadChangeLog(fileID)
    }

    func showDetailTab(_ tab: DetailPaneTab) {
        requestDetailTab(tab)
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }
}
