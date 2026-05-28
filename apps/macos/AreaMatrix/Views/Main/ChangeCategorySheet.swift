import SwiftUI

struct ChangeCategorySheet: View {
    let file: FileEntrySnapshot?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let state: MainFileCategoryMoveState
    let classifierContextState: ClassifierCorrectionContextState
    let mode: MainFileCategoryMoveMode
    let onCancel: () -> Void
    let onPreview: (Int64, String) -> Void
    let onLoadClassifierContext: (Int64, String) -> Void
    let onChangeCategory: (Int64, String, MainFileCategoryMoveMode, MainFileCategoryMoveOptions) -> Void
    let onBeginRuleHandoff: (Int64, String, Bool, ClassifierRuleHandoffDestination) -> Void
    let onRenameFirst: (Int64, String) -> Void
    let onOpenPermissionRecovery: () -> Void
    let onCollectDiagnostics: () -> Void
    @State var targetCategory: String
    @State var moveFile: Bool
    @State var rememberCorrection = false

    init(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot],
        state: MainFileCategoryMoveState,
        classifierContextState: ClassifierCorrectionContextState = .idle,
        mode: MainFileCategoryMoveMode = .moveToCategory,
        initialTargetCategory: String? = nil,
        onCancel: @escaping () -> Void,
        onPreview: @escaping (Int64, String) -> Void,
        onLoadClassifierContext: @escaping (Int64, String) -> Void = { _, _ in },
        onChangeCategory: @escaping (Int64, String, MainFileCategoryMoveMode, MainFileCategoryMoveOptions) -> Void,
        onBeginRuleHandoff: @escaping (Int64, String, Bool, ClassifierRuleHandoffDestination) -> Void = { _, _, _, _ in
        },
        onRenameFirst: @escaping (Int64, String) -> Void,
        onOpenPermissionRecovery: @escaping () -> Void,
        onCollectDiagnostics: @escaping () -> Void
    ) {
        self.file = file
        self.categoryRows = categoryRows
        self.state = state
        self.classifierContextState = classifierContextState
        self.mode = mode
        self.onCancel = onCancel
        self.onPreview = onPreview
        self.onLoadClassifierContext = onLoadClassifierContext
        self.onChangeCategory = onChangeCategory
        self.onBeginRuleHandoff = onBeginRuleHandoff
        self.onRenameFirst = onRenameFirst
        self.onOpenPermissionRecovery = onOpenPermissionRecovery
        self.onCollectDiagnostics = onCollectDiagnostics
        _targetCategory = State(initialValue: Self.defaultTargetCategory(
            for: file,
            categoryRows: categoryRows,
            initialTargetCategory: initialTargetCategory
        ))
        _moveFile = State(initialValue: Self.defaultMoveFile(for: file))
    }

    var body: some View {
        MainFileActionSheetContainer(title: pageTitle, pageID: pageID) {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    metadataRow("Name", file.currentName)
                    metadataRow("Current category", file.categoryPathDisplay)
                    metadataRow("Storage mode", file.storageMode)
                    classifierReasonRow
                    Picker("Target category", selection: $targetCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    classifierOptions(for: file)
                    metadataRow("Target path", targetPathText(for: file))
                    statusView(for: file)
                    actionButtons(for: file)
                }
                .task(id: previewTaskID(for: file)) {
                    requestClassifierContextIfNeeded(for: file)
                    requestPreviewIfNeeded(for: file)
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    func ruleHandoffSubmitButton(
        _ title: String,
        file: FileEntrySnapshot,
        destination: ClassifierRuleHandoffDestination
    ) -> some View {
        Button(title) {
            onBeginRuleHandoff(file.id, targetCategory, moveFile, destination)
        }
        .disabled(ruleHandoffDisabled(for: file))
    }

    func previewTaskID(for file: FileEntrySnapshot) -> String {
        "\(file.id)-\(file.currentName)-\(targetCategory)-\(mode)"
    }

    func requestPreviewIfNeeded(for file: FileEntrySnapshot) {
        guard targetCategory != file.category, !targetCategory.isEmpty else { return }
        onPreview(file.id, targetCategory)
    }

    func requestClassifierContextIfNeeded(for file: FileEntrySnapshot) {
        guard mode == .classifierCorrection else { return }
        onLoadClassifierContext(file.id, file.currentName)
    }

    func previewRequest(for file: FileEntrySnapshot) -> MainFileCategoryMovePreviewRequest {
        MainFileCategoryMovePreviewRequest(fileID: file.id, targetCategory: targetCategory)
    }

    func primaryActionTitle(for file: FileEntrySnapshot) -> String {
        if state.isMoving(fileID: file.id) {
            return mode == .classifierCorrection ? "Applying..." : "Moving..."
        }
        if state.failureOperation(for: file.id, targetCategory: targetCategory) == failureOperation {
            return "Retry"
        }
        return mode == .classifierCorrection ? "Apply correction" : "Change Category"
    }

    func actionDisabled(for file: FileEntrySnapshot) -> Bool {
        if targetCategory == file.category || targetCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if mode == .classifierCorrection {
            if state.isChecking(fileID: file.id, targetCategory: targetCategory) {
                return true
            }
            if state.isMoving(fileID: file.id) {
                return true
            }
            if moveFile && !canToggleMoveFile(for: file) {
                return true
            }
            let request = previewRequest(for: file)
            return state.preview(for: request) == nil ||
                state.failureOperation(for: file.id, targetCategory: targetCategory) == .preview
        }
        if state.isChecking(fileID: file.id, targetCategory: targetCategory) {
            return true
        }
        if state.isMoving(fileID: file.id) {
            return true
        }
        let request = previewRequest(for: file)
        if state.preview(for: request) != nil {
            return false
        }
        return state.failureOperation(for: file.id, targetCategory: targetCategory) != .move
    }

    func failureMessage(_ failure: CoreErrorMappingSnapshot, file: FileEntrySnapshot) -> String {
        if hasUnresolvedNameConflict(for: file) {
            return "Cannot create a safe target name. Rename the file first."
        }
        return failure.userMessage
    }

    func hasUnresolvedNameConflict(for file: FileEntrySnapshot) -> Bool {
        state.unresolvedNameConflict(for: file.id, targetCategory: targetCategory) != nil
    }

    func ruleHandoffDisabled(for file: FileEntrySnapshot) -> Bool {
        mode != .classifierCorrection || !rememberCorrection || actionDisabled(for: file)
    }

    var availableCategories: [String] {
        MainFileActionCategoryOptions.availableCategories(file: file, categoryRows: categoryRows)
    }

    var pageID: String {
        mode == .classifierCorrection ? "S2-16" : "S1-35"
    }

    var pageTitle: String {
        mode == .classifierCorrection ? "Correct classification" : "Change Category"
    }

    var classifierOptions: MainFileCategoryMoveOptions {
        MainFileCategoryMoveOptions(
            moveFile: moveFile,
            remember: rememberCorrection
        )
    }

    var failureOperation: MainFileCategoryMoveFailureOperation {
        mode == .classifierCorrection ? .correction : .move
    }

    func canToggleMoveFile(for file: FileEntrySnapshot) -> Bool {
        file.storageMode != "Indexed" && file.availability == .available && file.origin == "Imported"
    }

    func moveDisabledReason(for file: FileEntrySnapshot) -> String {
        if file.availability == .missing { return "Missing files can only update classification metadata." }
        if file.storageMode == "Indexed" { return "Index-only files are not moved by classifier correction." }
        if file.origin != "Imported" { return "Adopted or external files default to metadata-only correction." }
        return "This file cannot be moved from this correction sheet."
    }

    func ruleSuggestionText(for _: FileEntrySnapshot) -> String {
        "Safe keyword, extension, and priority candidates are reviewed before any rule is saved."
    }

    func classifierContextRequest(
        for file: FileEntrySnapshot?
    ) -> ClassifierCorrectionContextRequest {
        ClassifierCorrectionContextRequest(
            fileID: file?.id ?? -1,
            filename: file?.currentName ?? ""
        )
    }

    func classificationReasonText(_ result: ClassifyResultSnapshot) -> String {
        switch result.reason {
        case .keyword:
            "Matched keyword rule -> \(result.category) (\(result.confidencePercent)% confidence)"
        case .extension:
            "Matched extension rule -> \(result.category) (\(result.confidencePercent)% confidence)"
        case .aiPredicted:
            "AI prediction -> \(result.category) (\(result.confidencePercent)% confidence)"
        case .default:
            "Default rule -> \(result.category)"
        }
    }

    private static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot],
        initialTargetCategory: String?
    ) -> String {
        if let initialTargetCategory, initialTargetCategory != file?.category {
            return initialTargetCategory
        }
        return MainFileActionCategoryOptions.defaultTargetCategory(for: file, categoryRows: categoryRows)
    }

    private static func defaultMoveFile(for file: FileEntrySnapshot?) -> Bool {
        guard let file else { return false }
        return file.storageMode != "Indexed" && file.availability == .available && file.origin == "Imported"
    }
}

struct ClassifierRuleEditorRouteView: View {
    let repoPath: String
    let context: BatchChangeCategoryReturnContext?
    let onCancelFromBatchCategory: (BatchChangeCategoryReturnContext) -> Void
    let onAcceptedCategoryFromBatchCategory: (String, BatchChangeCategoryReturnContext) -> Void

    init(
        repoPath: String,
        context: BatchChangeCategoryReturnContext?,
        onCancelFromBatchCategory: @escaping (BatchChangeCategoryReturnContext) -> Void = { _ in },
        onAcceptedCategoryFromBatchCategory: @escaping (String, BatchChangeCategoryReturnContext)
            -> Void = { _, _ in }
    ) {
        self.repoPath = repoPath
        self.context = context
        self.onCancelFromBatchCategory = onCancelFromBatchCategory
        self.onAcceptedCategoryFromBatchCategory = onAcceptedCategoryFromBatchCategory
    }

    var body: some View {
        VStack(spacing: 0) {
            ClassifierSettingsPane(
                repoPath: repoPath,
                onSavedCategory: postSavedCategory
            )
            if let context {
                Divider()
                createBar(context)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: ClassifierRuleEditorSaveEvents.savedCategoryNotification
        )) { notification in
            handleClassifierSave(notification)
        }
    }

    private func createBar(_ context: BatchChangeCategoryReturnContext) -> some View {
        HStack(spacing: 12) {
            Text("Edit classifier.yaml in S2-19. Validate returns to S2-12 when one new category is saved.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { onCancelFromBatchCategory(context) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 34).padding(.vertical, 12)
        .accessibilityIdentifier("S2-12-classifier-editor-return-context")
    }

    private func handleClassifierSave(_ notification: Notification) {
        guard let context,
              let savedCategory = ClassifierRuleEditorSaveEvents.savedCategory(from: notification)
        else {
            return
        }
        onAcceptedCategoryFromBatchCategory(savedCategory, context)
    }

    private func postSavedCategory(_ category: String) {
        NotificationCenter.default.post(
            ClassifierRuleEditorSaveEvents.notification(savedCategory: category)
        )
    }
}
