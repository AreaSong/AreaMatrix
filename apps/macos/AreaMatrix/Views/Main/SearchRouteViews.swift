import SwiftUI

struct SearchIndexingStatusRouteView: View {
    let request: SearchQueryRequestSnapshot
    let indexStatus: SearchIndexStatusSnapshot?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        MainFileActionSheetContainer(title: "Search Index Status", pageID: "S2-01-indexing-status") {
            Label(statusText, systemImage: "exclamationmark.triangle")
                .font(.callout)
            metadataRow("Query", request.query)
            metadataRow("Scope", request.scope.displayName)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Retry", action: onRetry)
            }
        }
        .accessibilityIdentifier("S2-01-indexing-status-search-route")
    }

    private var statusText: String {
        switch indexStatus {
        case .unavailable:
            "Search index unavailable"
        case .indexing:
            "Search index is updating"
        case .ready:
            "Search index ready"
        case nil:
            "Search index status unavailable"
        }
    }
}

func searchContextText(_ request: SearchQueryRequestSnapshot) -> String {
    "Scope: \(request.scope.displayName) | Sort: \(request.sort.displayName)"
}

struct AISummaryEditor: View {
    private let repoPath: String
    private let fileID: Int64
    private let privacyContext: AISummaryPrivacyContext
    private let exitController: AISummaryEditorExitController?
    private let onOpenAISettings: () -> Void
    private let onBackToDetail: () -> Void
    @StateObject private var model: AISummaryEditorModel
    @State private var confirmation: AISummaryConfirmation?
    @State private var privacyRuleRoute: AIPrivacyRulesRoute?
    @State private var callLogRoute: AISummaryCallLogRoute?
    @FocusState private var isEditorFocused: Bool
    init(
        repoPath: String,
        fileID: Int64,
        privacyContext: AISummaryPrivacyContext = AISummaryPrivacyContext(),
        exitController: AISummaryEditorExitController? = nil,
        onOpenAISettings: @escaping () -> Void = {},
        onBackToDetail: @escaping () -> Void = {}
    ) {
        self.repoPath = repoPath; self.fileID = fileID; self.privacyContext = privacyContext
        self.exitController = exitController
        self.onOpenAISettings = onOpenAISettings
        self.onBackToDetail = onBackToDetail
        _model = StateObject(wrappedValue: AISummaryEditorModel(
            repoPath: repoPath,
            fileID: fileID,
            privacyContext: privacyContext
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            gateNoticeView
            provenanceRows
            editor
            progressView
            errorView
            controls
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button(confirmation?.actionTitle ?? "", role: confirmation?.isDestructive == true ? .destructive : nil) {
                performConfirmedAction()
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .sheet(item: $privacyRuleRoute) { route in
            AIPrivacyRulesRouteSheet(repoPath: repoPath, focus: route.focus) {
                privacyRuleRoute = nil
            }
        }
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .summary
            ) {
                callLogRoute = nil
            }
        }
        .onChange(of: AISummaryEditorIdentity(fileID: fileID, privacyContext: privacyContext)) { _, identity in
            model.reset(fileID: identity.fileID)
            model.updatePrivacyContext(identity.privacyContext)
            syncExitController()
        }
        .task(id: AISummaryEditorIdentity(fileID: fileID, privacyContext: privacyContext)) {
            await model.loadEntryState()
        }
        .onAppear(perform: syncExitController)
        .onChange(of: model.status) { _, _ in syncExitController() }
        .onChange(of: model.operation) { _, _ in syncExitController() }
        .onChange(of: model.draftText) { _, _ in syncExitController() }
        .accessibilityIdentifier("S3-06-C3-06-ai-summary-editor")
    }

    private var header: some View {
        HStack {
            Text("AI Summary").font(.headline).accessibilityAddTraits(.isHeader)
            Text(model.status.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(model.characterCountText).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gateNoticeView: some View {
        switch model.gateState {
        case .unknown:
            EmptyView()
        case .checking:
            Label("Checking AI summary gate...", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S3-06-C3-06-generate-gate-checking")
        case .allowed:
            EmptyView()
        case let .blocked(notice):
            noticeView(notice, accessibilityID: gateAccessibilityID(for: notice))
        case let .failed(error):
            VStack(alignment: .leading, spacing: 4) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                Text(error.detail).font(.caption)
                Text(error.recovery).font(.caption)
            }
            .foregroundStyle(.orange)
            .accessibilityIdentifier("S3-06-C3-06-generate-gate-error")
        }
    }

    private func noticeView(_ notice: AISummaryEditorNotice, accessibilityID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(notice.title, systemImage: "exclamationmark.triangle")
            Text(notice.detail).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(notice.recovery).font(.caption).foregroundStyle(.secondary)
                Spacer()
                noticeAction(notice)
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.12))
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func noticeAction(_ notice: AISummaryEditorNotice) -> some View {
        if notice.opensAISettings {
            Button("Open AI settings", action: onOpenAISettings)
                .accessibilityIdentifier("S3-06-\(notice.capability)-open-ai-settings")
        } else if let route = notice.s309PrivacyRulesRoute(repoPath: repoPath),
                  let suffix = notice.s309PrivacyRulesRouteAccessibilitySuffix {
            Button("View privacy rule") {
                privacyRuleRoute = route
            }
            .accessibilityIdentifier("S3-06-\(notice.capability)-view-\(suffix)")
        }
    }

    private func gateAccessibilityID(for notice: AISummaryEditorNotice) -> String {
        notice.capability == "C3-09" ? "S3-06-C3-09-privacy-gate" : "S3-06-C3-06-generate-gate"
    }

    @ViewBuilder
    private var provenanceRows: some View {
        if let provenance = model.provenance {
            VStack(alignment: .leading, spacing: 4) {
                Text(provenanceTitle(provenance))
                Text("Model: \(provenance.modelName ?? "Not recorded")")
                Text("Used fields: \(summaryUsedFields(provenance.usedContext))")
                if let generatedAt = provenance.generatedAt {
                    Text("Generated: \(generatedAt)")
                }
                if let privacySkip = model.privacySkip {
                    Text(privacySkip.reasonLabel)
                    Text(privacySkip.message)
                    Text("Sent fields: \(privacySentFields(privacySkip.sentFields))")
                    if let ruleID = privacySkip.ruleID {
                        Button("View privacy rule") {
                            privacyRuleRoute = AIPrivacyRulesRoute(repoPath: repoPath, focus: .rule(ruleID: ruleID))
                        }
                        .accessibilityIdentifier("S3-06-C3-09-view-privacy-rule-\(ruleID)")
                    } else if let field = privacySkip.matchedField {
                        Button("View privacy rule") {
                            privacyRuleRoute = AIPrivacyRulesRoute(repoPath: repoPath, focus: .field(field))
                        }
                        .accessibilityIdentifier("S3-06-C3-09-view-privacy-field-\(field)")
                    }
                }
                if let callLogID = provenance.callLogID {
                    Button("View AI call") {
                        callLogRoute = AISummaryCallLogRoute(callLogID: callLogID)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("S3-06-\(callLogCapability)-view-ai-call-\(callLogID)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(model.privacySkip == nil ? "S3-06-C3-06-provenance" : "S3-06-C3-09-privacy-skip")
        }
    }

    private func provenanceTitle(_ provenance: AISummaryProvenance) -> String {
        if model.privacySkip == nil {
            return provenance.route.map(aiSummaryRouteLabel) ?? "Draft"
        }
        return model.status.label
    }

    private var callLogCapability: String {
        model.privacySkip == nil ? "C3-06" : "C3-09"
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.draftText }, set: model.updateDraft))
            .font(.body)
            .frame(minHeight: 150)
            .overlay(alignment: .topLeading) {
                if model.draftText.isEmpty {
                    Text("No AI summary yet.").foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5)
                }
            }
            .disabled(model.operation.isBusy)
            .focused($isEditorFocused)
            .accessibilityLabel("AI summary draft")
    }

    @ViewBuilder
    private var progressView: some View {
        if let progressText = model.operation.progressText {
            Label(progressText, systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S3-06-C3-06-operation-progress")
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if case let .failed(error) = model.operation {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(error.detail).font(.caption).foregroundStyle(.secondary)
                Text(error.recovery).font(.caption).foregroundStyle(.secondary)
                failedActionControls
            }
            .accessibilityIdentifier("S3-06-C3-06-error")
        }
    }

    @ViewBuilder
    private var failedActionControls: some View {
        switch model.failedAction {
        case .load:
            HStack {
                Button("Retry load") { Task { await model.loadEntryState() } }
                Button("Back to detail", action: onBackToDetail)
            }
        case .generate:
            HStack {
                Button("Retry generate") { Task { await model.generate(regenerate: false) } }
                Button("Cancel", action: model.cancelFailedAction)
            }
        case .save:
            HStack {
                Button("Retry save") { Task { await model.save() } }
                Button("Discard changes", action: model.discardChanges)
                Button("Back to detail", action: onBackToDetail)
            }
        case .clear:
            HStack {
                Button("Retry clear") { Task { await model.clear() } }
                Button("Cancel", action: model.cancelFailedAction)
            }
        case nil:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack {
            Button("Generate summary") { Task { await model.generate(regenerate: false) } }
                .disabled(!model.canGenerate)
            Button("Regenerate...") { confirmation = .regenerate }
                .disabled(!model.canRegenerate)
            if model.canCancelGeneration {
                Button("Cancel generation", action: model.cancelGeneration)
            }
            Spacer()
            Button("Discard changes", action: model.discardChanges).disabled(!model.canDiscard)
            Button("Clear summary...") { confirmation = .clear }.disabled(!model.canClear)
            Button(saveTitle) { Task { await model.save() } }.disabled(!model.canSave)
        }
    }

    private var saveTitle: String {
        model.operation == .saving ? "Saving summary..." : "Save"
    }

    private func performConfirmedAction() {
        let action = confirmation
        confirmation = nil
        switch action {
        case .regenerate:
            Task { await model.generate(regenerate: true) }
        case .clear:
            Task { await model.clear() }
        case nil:
            break
        }
    }

    private func syncExitController() {
        exitController?.update(needsConfirmation: model.needsExitConfirmation) {
            await model.save()
        } discardHandler: {
            model.discardChanges()
        }
    }
}

struct AISummarySelectionExitRequest: Identifiable, Equatable {
    let previousIDs: Set<Int64>
    let requestedIDs: Set<Int64>

    var id: String {
        "\(Self.idList(previousIDs))->\(Self.idList(requestedIDs))"
    }

    static func shouldPrompt(
        previousIDs: Set<Int64>,
        requestedIDs: Set<Int64>,
        needsConfirmation: Bool
    ) -> Bool {
        needsConfirmation && previousIDs != requestedIDs
    }

    private static func idList(_ ids: Set<Int64>) -> String {
        ids.sorted().map(String.init).joined(separator: ",")
    }
}

struct AISummarySelectionExitState: Equatable {
    private(set) var pendingRequest: AISummarySelectionExitRequest?
    private var isRestoring = false
    private var isApplying = false

    mutating func handleChange(
        previousIDs: Set<Int64>,
        requestedIDs: Set<Int64>,
        needsConfirmation: Bool
    ) -> AISummarySelectionExitAction {
        if isRestoring {
            isRestoring = false
            return .ignoreRestoredSelection
        }
        if isApplying {
            isApplying = false
            return .apply(previousIDs: previousIDs, requestedIDs: requestedIDs)
        }
        guard AISummarySelectionExitRequest.shouldPrompt(
            previousIDs: previousIDs,
            requestedIDs: requestedIDs,
            needsConfirmation: needsConfirmation
        ) else {
            return .apply(previousIDs: previousIDs, requestedIDs: requestedIDs)
        }
        let request = AISummarySelectionExitRequest(previousIDs: previousIDs, requestedIDs: requestedIDs)
        pendingRequest = request
        isRestoring = true
        return .restore(request.previousIDs)
    }

    mutating func cancelPending() -> Set<Int64>? {
        guard let request = pendingRequest else { return nil }
        pendingRequest = nil
        isRestoring = true
        return request.previousIDs
    }

    mutating func takePendingForApply() -> AISummarySelectionExitRequest? {
        guard let request = pendingRequest else { return nil }
        pendingRequest = nil
        isApplying = true
        return request
    }

    mutating func finishDirectApply() {
        isApplying = false
    }

    mutating func cancelRestoreFlag() {
        isRestoring = false
    }
}

enum AISummarySelectionExitAction: Equatable {
    case apply(previousIDs: Set<Int64>, requestedIDs: Set<Int64>)
    case restore(Set<Int64>)
    case ignoreRestoredSelection
}

extension MainRepositoryContentView {
    func handleSelectedFileIDsChange(previousIDs: Set<Int64>, ids: Set<Int64>) {
        let action = summarySelectionExitState.handleChange(
            previousIDs: previousIDs,
            requestedIDs: ids,
            needsConfirmation: summaryExitController.needsConfirmation
        )
        performSummarySelectionExitAction(action)
    }

    func cancelPendingSummarySelectionExit() {
        guard let ids = summarySelectionExitState.cancelPending() else { return }
        restoreSelectedFileIDs(ids)
    }

    func saveAndFinishPendingSummarySelectionExit() async {
        guard await summaryExitController.saveChanges() else { return }
        finishPendingSummarySelectionExit()
    }

    func finishPendingSummarySelectionExit() {
        guard let request = summarySelectionExitState.takePendingForApply() else { return }
        applyPendingSummarySelectionExit(request)
    }

    private func performSummarySelectionExitAction(_ action: AISummarySelectionExitAction) {
        switch action {
        case let .apply(previousIDs, requestedIDs):
            applySelectedFileIDs(requestedIDs, leaving: previousIDs)
        case let .restore(ids):
            restoreSelectedFileIDs(ids)
        case .ignoreRestoredSelection:
            break
        }
    }

    private func applySelectedFileIDs(_ ids: Set<Int64>, leaving previousIDs: Set<Int64>) {
        showFailedNoteDraftBannerIfNeeded(leaving: previousIDs)
        if !ids.isEmpty {
            selectedImportProgressIDs = []
        }
        Task {
            await fileListModel.selectFiles(ids)
        }
    }

    private func applyPendingSummarySelectionExit(_ request: AISummarySelectionExitRequest) {
        if selectedFileIDs == request.requestedIDs {
            summarySelectionExitState.finishDirectApply()
            applySelectedFileIDs(request.requestedIDs, leaving: request.previousIDs)
            return
        }
        selectedFileIDs = request.requestedIDs
    }

    private func restoreSelectedFileIDs(_ ids: Set<Int64>) {
        if !ids.isEmpty {
            selectedImportProgressIDs = []
        }
        guard selectedFileIDs != ids else {
            summarySelectionExitState.cancelRestoreFlag()
            return
        }
        selectedFileIDs = ids
    }
}
