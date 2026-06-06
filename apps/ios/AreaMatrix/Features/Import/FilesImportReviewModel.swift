import Foundation

@MainActor
final class FilesImportReviewModel: ObservableObject {
    @Published private(set) var phase: FilesImportPhase = .reading
    @Published private(set) var previewItems: [FilesImportPreviewItem] = []
    @Published private(set) var error: FilesImportError?
    @Published private(set) var warning: String?
    @Published private(set) var importedFiles: [MobileLibraryFile] = []
    @Published private(set) var replaceCandidates: [FilesImportReplaceCandidate] = []
    @Published private(set) var pendingReplaceConfirmation: FilesImportReplaceConfirmation?
    @Published private(set) var replaceErrorMessage: String?
    @Published private(set) var category: String = "inbox"
    @Published var filename: String = "" {
        didSet { validateFilename() }
    }

    private let repoPath: String
    private let selectedURLs: [URL]
    private let bridge: any FilesImportCoreBridge
    private let accessProvider: any FilesImportSecurityScopedAccessing
    private let allowReplaceDuringImport: Bool

    init(
        repoPath: String,
        selectedURLs: [URL],
        bridge: any FilesImportCoreBridge,
        accessProvider: any FilesImportSecurityScopedAccessing = FilesImportSecurityScopedAccessService(),
        allowReplaceDuringImport: Bool = false
    ) {
        self.repoPath = repoPath
        self.selectedURLs = selectedURLs
        self.bridge = bridge
        self.accessProvider = accessProvider
        self.allowReplaceDuringImport = allowReplaceDuringImport
    }

    var canImport: Bool {
        phase == .ready
            && error == nil
            && filenameValidation == nil
            && replaceErrorMessage == nil
            && replaceCandidates.isEmpty
            && previewItems.contains { $0.status.isImportable }
            && !normalizedCategory.isEmpty
    }

    var hasPendingReplaceReview: Bool {
        !replaceCandidates.isEmpty
    }

    var canShowReplaceOption: Bool {
        allowReplaceDuringImport
    }

    var replaceUnavailableReason: String? {
        if !allowReplaceDuringImport {
            return "Replace is disabled in repository settings."
        }
        return nil
    }

    var allowsFilenameEditing: Bool {
        previewItems.count == 1
    }

    var filenameValidation: String? {
        if allowsFilenameEditing && Self.safeFilename(filename).isEmpty {
            return "File name is required."
        }
        return nil
    }

    var importButtonTitle: String {
        phase == .importing ? "Importing..." : "Import"
    }

    var selectedSummary: String {
        if previewItems.isEmpty {
            return "Choose files to import."
        }
        if previewItems.count == 1, let first = previewItems.first {
            return first.displayName
        }
        return "\(previewItems.count) items selected"
    }

    var totalSizeText: String {
        let sizes = previewItems.compactMap(\.sizeBytes)
        guard sizes.count == previewItems.count else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: sizes.reduce(0, +), countStyle: .file)
    }

    var statusText: String {
        switch phase {
        case .reading:
            "Reading selected files..."
        case .ready:
            "Ready to import"
        case .importing:
            "Copying files..."
        case .succeeded:
            "Imported \(importedFiles.count) items"
        case .failed:
            "Files import failed"
        }
    }

    func prepare() async {
        guard phase == .reading else { return }
        guard !selectedURLs.isEmpty else {
            error = .emptySelection
            phase = .failed
            return
        }
        previewItems = selectedURLs.map { makePreviewItem(for: $0) }
        filename = Self.defaultFilename(for: previewItems)
        await applyCategoryPrediction()
        if !previewItems.contains(where: { $0.status.isImportable }) {
            error = .unreadableFile("No readable files")
        }
        phase = error == nil ? .ready : .failed
    }

    func updateCategory(_ value: String) {
        category = Self.normalizedCategory(value)
    }

    func importFiles() async {
        guard canImport else { return }
        await importReadyItems(resetResults: true)
    }

    func retry() async {
        resetFailedItems()
        await importFiles()
    }

    private func importReadyItems(resetResults: Bool) async {
        phase = .importing
        error = nil
        warning = nil
        if resetResults {
            importedFiles = []
        }
        replaceErrorMessage = nil
        for item in previewItems where item.status.isImportable {
            await importItem(item)
            if hasPendingReplaceReview || error != nil {
                break
            }
        }
        if error != nil {
            phase = .failed
        } else if hasPendingReplaceReview {
            phase = .ready
        } else {
            phase = importedFiles.isEmpty && !hasSkippedDuplicates ? .failed : .succeeded
        }
    }

    func updateConflictStrategy(
        for candidateID: FilesImportReplaceCandidate.ID,
        strategy: FilesImportConflictStrategy
    ) {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        guard canSelect(strategy, for: replaceCandidates[index]) else { return }
        switch strategy {
        case .skip:
            resolveCandidateAsSkipped(candidateID)
        case .keepBoth:
            Task { await resolveCandidateAsKeepBoth(candidateID) }
        case .replace:
            Task { await presentReplaceConfirmation(candidateID) }
        }
    }

    func confirmReplace(_ confirmation: FilesImportReplaceConfirmation, understandsReplace: Bool) {
        guard understandsReplace else {
            replaceErrorMessage = "Confirm that you understand this will replace the existing file."
            return
        }
        guard replaceUnavailableReason == nil else {
            replaceErrorMessage = replaceUnavailableReason
            return
        }
        guard let index = replaceCandidates.firstIndex(where: { $0.id == confirmation.id }) else {
            replaceErrorMessage = "Replace confirmation context expired."
            return
        }
        guard replaceCandidates[index].replacePlan?.canReplace == true else {
            replaceErrorMessage = "Replace plan is unavailable. Run Core preflight again."
            return
        }
        let candidateID = replaceCandidates[index].id
        replaceCandidates[index].isConfirmed = true
        pendingReplaceConfirmation = nil
        replaceErrorMessage = nil
        Task { await resolveConfirmedReplace(candidateID) }
    }

    func cancelReplaceConfirmation() {
        pendingReplaceConfirmation = nil
        replaceErrorMessage = nil
    }

    private var normalizedCategory: String {
        Self.normalizedCategory(category)
    }

    private var hasSkippedDuplicates: Bool {
        previewItems.contains { item in
            if case .skippedDuplicate = item.status {
                return true
            }
            return false
        }
    }

    private func applyCategoryPrediction() async {
        guard let first = previewItems.first(where: { $0.status.isImportable }) else { return }
        do {
            let prediction = try await bridge.predictCategory(repoPath: repoPath, filename: first.displayName)
            category = prediction.category.isEmpty ? "inbox" : prediction.category
            if allowsFilenameEditing && !prediction.suggestedName.isEmpty {
                filename = Self.safeFilename(prediction.suggestedName)
            }
        } catch {
            warning = FilesImportError.map(error).message
            category = "inbox"
        }
    }

    private func importItem(_ item: FilesImportPreviewItem) async {
        updateItem(item.id, status: .importing)
        do {
            let imported = try await importWithAccess(item, filename: importFilename(for: item), strategy: .skip)
            importedFiles.append(imported)
            updateItem(item.id, status: .imported)
        } catch {
            await handleImportFailure(error, for: item)
        }
    }

    private func handleImportFailure(_ thrownError: Error, for item: FilesImportPreviewItem) async {
        let mapped = FilesImportError.map(thrownError)
        if case let .duplicateContent(existingPath) = mapped {
            registerConflictCandidate(for: item, kind: .duplicateContent, existingPath: existingPath)
            return
        }
        if case let .nameConflict(existingPath) = mapped {
            registerConflictCandidate(for: item, kind: .nameConflict, existingPath: existingPath)
            return
        }
        error = mapped
        updateItem(item.id, status: .failed(mapped.message))
    }

    private func registerConflictCandidate(
        for item: FilesImportPreviewItem,
        kind: FilesImportConflictKind,
        existingPath: String
    ) {
        let importName = importFilename(for: item)
        replaceCandidates.append(FilesImportReplaceCandidate(
            itemID: item.id,
            kind: kind,
            existingPath: existingPath,
            incomingPath: item.sourceURL.path,
            incomingName: importName,
            incomingSizeBytes: item.sizeBytes,
            targetRelativePath: Self.targetRelativePath(category: normalizedCategory, filename: importName),
            keepBothFilename: Self.keepBothFilename(for: importName)
        ))
        updateItem(item.id, status: .failed("\(kind.title): \(existingPath)"))
    }

    private func canSelect(
        _ strategy: FilesImportConflictStrategy,
        for candidate: FilesImportReplaceCandidate
    ) -> Bool {
        candidate.kind.availableStrategies.contains(strategy)
            && (strategy != .replace || allowReplaceDuringImport)
    }

    private func resolveCandidateAsSkipped(_ candidateID: FilesImportReplaceCandidate.ID) {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = replaceCandidates.remove(at: index)
        updateItem(candidate.itemID, status: .skippedDuplicate(candidate.existingPath))
        Task { await finishOrContinueAfterConflictResolution() }
    }

    private func resolveCandidateAsKeepBoth(_ candidateID: FilesImportReplaceCandidate.ID) async {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = replaceCandidates[index]
        guard let resolved = candidate.keepBothFilename,
              let item = previewItems.first(where: { $0.id == candidate.itemID }) else {
            replaceErrorMessage = "Could not build a Keep both filename."
            return
        }
        do {
            let imported = try await importWithAccess(item, filename: resolved, strategy: .keepBoth)
            importedFiles.append(imported)
            updateItem(item.id, status: .imported)
            removeReplaceCandidate(candidateID)
            await finishOrContinueAfterConflictResolution()
        } catch {
            self.error = FilesImportError.map(error)
            updateItem(item.id, status: .failed(candidate.kind.title))
            phase = .failed
        }
    }

    private func presentReplaceConfirmation(_ candidateID: FilesImportReplaceCandidate.ID) async {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        if replaceCandidates[index].replacePlan == nil {
            await loadReplacePlan(for: candidateID)
        }
        guard let plannedIndex = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        guard replaceCandidates[plannedIndex].replacePlan?.canReplace == true else {
            replaceErrorMessage = replaceCandidates[plannedIndex].replaceBlockedReason
                ?? "Core replace preflight did not approve this file."
            return
        }
        pendingReplaceConfirmation = FilesImportReplaceConfirmation(candidate: replaceCandidates[plannedIndex])
        replaceErrorMessage = nil
    }

    private func resolveConfirmedReplace(_ candidateID: FilesImportReplaceCandidate.ID) async {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = replaceCandidates[index]
        guard let item = previewItems.first(where: { $0.id == candidate.itemID }) else {
            replaceErrorMessage = "Selected file is no longer available."
            return
        }
        guard let plan = candidate.replacePlan else {
            replaceErrorMessage = "Replace plan is unavailable. Run Core preflight again."
            return
        }
        do {
            let report = try await replaceWithAccess(item, candidate: candidate, plan: plan)
            importedFiles.append(report.importedFile)
            warning = report.statusSummary
            updateItem(item.id, status: .imported)
            removeReplaceCandidate(candidateID)
            await finishOrContinueAfterConflictResolution()
        } catch {
            self.error = FilesImportError.map(error)
            updateItem(item.id, status: .failed(FilesImportError.map(error).message))
            phase = .failed
        }
    }

    private func loadReplacePlan(for candidateID: FilesImportReplaceCandidate.ID) async {
        guard let index = replaceCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = replaceCandidates[index]
        guard let item = previewItems.first(where: { $0.id == candidate.itemID }) else {
            replaceErrorMessage = "Selected file is no longer available."
            return
        }
        do {
            let access = try accessProvider.beginAccessing(item.sourceURL)
            defer { access.stop() }
            let plan = try await bridge.prepareReplace(request: FilesImportReplacePlanRequest(
                repoPath: repoPath,
                sourceURL: item.sourceURL,
                incomingName: candidate.incomingName,
                category: normalizedCategory,
                existingPath: candidate.existingPath,
                targetRelativePath: candidate.targetRelativePath
            ))
            if let latestIndex = replaceCandidates.firstIndex(where: { $0.id == candidateID }) {
                replaceCandidates[latestIndex].replacePlan = plan
            }
        } catch {
            replaceErrorMessage = FilesImportError.map(error).message
        }
    }

    private func removeReplaceCandidate(_ candidateID: FilesImportReplaceCandidate.ID) {
        replaceCandidates.removeAll { $0.id == candidateID }
    }

    private func finishOrContinueAfterConflictResolution() async {
        guard replaceCandidates.isEmpty else { return }
        if previewItems.contains(where: { $0.status.isImportable }) {
            await importReadyItems(resetResults: false)
            return
        }
        if error == nil, importedFiles.isEmpty && hasSkippedDuplicates {
            phase = .succeeded
        } else if error == nil, !importedFiles.isEmpty {
            phase = .succeeded
        }
    }

    private func importWithAccess(
        _ item: FilesImportPreviewItem,
        filename: String,
        strategy: FilesImportDuplicateStrategy
    ) async throws -> MobileLibraryFile {
        let access = try accessProvider.beginAccessing(item.sourceURL)
        defer { access.stop() }
        return try await bridge.importSelectedFile(request: FilesImportCoreRequest(
            repoPath: repoPath,
            sourceURL: item.sourceURL,
            filename: filename,
            category: normalizedCategory,
            duplicateStrategy: strategy
        ))
    }

    private func replaceWithAccess(
        _ item: FilesImportPreviewItem,
        candidate: FilesImportReplaceCandidate,
        plan: FilesImportReplacePlan
    ) async throws -> FilesImportReplaceExecutionReport {
        let access = try accessProvider.beginAccessing(item.sourceURL)
        defer { access.stop() }
        return try await bridge.replaceSelectedFile(request: FilesImportReplaceRequest(
            repoPath: repoPath,
            sourceURL: item.sourceURL,
            filename: candidate.incomingName,
            category: normalizedCategory,
            plan: plan
        ))
    }

    private func makePreviewItem(for url: URL) -> FilesImportPreviewItem {
        let status = previewStatus(for: url)
        return FilesImportPreviewItem(
            sourceURL: url,
            displayName: Self.safeFilename(url.lastPathComponent),
            sourceLocation: Self.sourceLocation(for: url),
            sizeBytes: Self.fileSize(for: url),
            status: status
        )
    }

    private func previewStatus(for url: URL) -> FilesImportPreviewStatus {
        do {
            let access = try accessProvider.beginAccessing(url)
            defer { access.stop() }
            if Self.isICloudPlaceholder(url) {
                return .downloadNeeded
            }
            return FileManager.default.isReadableFile(atPath: url.path) ? .ready : .unreadable
        } catch {
            self.error = FilesImportError.map(error)
            return .failed(FilesImportError.map(error).message)
        }
    }

    private func updateItem(_ id: String, status: FilesImportPreviewStatus) {
        guard let index = previewItems.firstIndex(where: { $0.id == id }) else { return }
        previewItems[index].status = status
    }

    private func resetFailedItems() {
        error = nil
        for item in previewItems {
            if case .failed = item.status {
                updateItem(item.id, status: .ready)
            }
        }
    }

    private func importFilename(for item: FilesImportPreviewItem) -> String {
        if allowsFilenameEditing {
            return Self.safeFilename(filename)
        }
        return item.displayName
    }

    private func validateFilename() {
        if filenameValidation == nil, error == .emptySelection {
            error = nil
        }
    }

}
