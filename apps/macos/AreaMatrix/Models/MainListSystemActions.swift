import Foundation

enum SavedSearchResultCountState: Equatable {
    case loading
    case loaded(Int64)
    case failed

    var summary: String {
        switch self {
        case .loading:
            "Counting results..."
        case let .loaded(count):
            count == 1 ? "1 file" : "\(count) files"
        case .failed:
            "Result count unavailable"
        }
    }

    var emptyResultWarning: String? {
        guard case .loaded(0) = self else { return nil }
        return "This Smart List is currently empty."
    }
}

struct SavedSearchSheetModel {
    static let icons = ["magnifyingglass", "doc.text.magnifyingglass", "folder"]

    var request: SearchQueryRequestSnapshot
    var resultCountState: SavedSearchResultCountState
    var name: String
    var icon = "magnifyingglass"
    var pinned = true
    var existingNames: Set<String> = []
    var isSaving = false
    var saveFailure: CoreErrorMappingSnapshot?

    init(request: SearchQueryRequestSnapshot, resultCountState: SavedSearchResultCountState) {
        self.request = request
        self.resultCountState = resultCountState
        name = Self.defaultName(for: request)
    }

    init(request: SearchQueryRequestSnapshot, resultCount: Int64?) {
        self.init(
            request: request,
            resultCountState: resultCount.map(SavedSearchResultCountState.loaded) ?? .loading
        )
    }

    var validationMessage: String? {
        let trimmed = trimmedName
        if trimmed.isEmpty { return "Name is required." }
        if trimmed.count > 64 { return "Name must be 64 characters or fewer." }
        if existingNames.contains(trimmed.lowercased()) {
            return "A Smart List named \"\(trimmed)\" already exists."
        }
        return nil
    }

    var canSave: Bool {
        validationMessage == nil && !isSaving
    }

    var primaryActionTitle: String {
        isSaving ? "Saving..." : "Save"
    }

    var createRequest: CreateSavedSearchRequestSnapshot {
        CreateSavedSearchRequestSnapshot(
            name: trimmedName,
            query: SavedSearchQuerySnapshot(request: request),
            icon: icon,
            color: nil,
            pinned: pinned
        )
    }

    var querySummary: String {
        request.query.isEmpty ? "Filtered search" : request.query
    }

    var filterSummary: String {
        request.filters.isEmpty ? "None" : "\(request.filters.activeFilterCount) active"
    }

    var resultCountSummary: String {
        resultCountState.summary
    }

    var emptyResultWarning: String? {
        resultCountState.emptyResultWarning
    }

    var showsRetry: Bool {
        saveFailure != nil && !isSaving
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultName(for request: SearchQueryRequestSnapshot) -> String {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed.prefix(64).description }
        return request.filters.isEmpty ? "Saved Search" : "Filtered Search"
    }
}

extension OnboardingModel {
    @MainActor
    func openLearnMore() {
        do {
            try helpOpener.openWelcomeHelp()
        } catch {
            toastMessage = "Learn more is unavailable right now."
        }
    }

    @MainActor
    func showMainListFileInFinder(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileRevealer.revealFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = "File cannot be shown in Finder."
        }
    }

    @MainActor
    func openMainListFile(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileOpener.openFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = "File cannot be opened."
        }
    }

    @MainActor
    func copyMainListPath(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try pathCopier.copyPath(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = "Path copied."
            accessibilityAnnouncer.announce("Path copied.")
        } catch {
            toastMessage = "Path cannot be copied."
            accessibilityAnnouncer.announce("Path cannot be copied.")
        }
    }

    @MainActor
    func copyMainListPaths(opening: RepositoryOpeningResult, relativePaths: [String]) {
        do {
            try pathCopier.copyPaths(repoPath: opening.config.repoPath, relativePaths: relativePaths)
            toastMessage = "\(relativePaths.count) paths copied."
            accessibilityAnnouncer.announce("\(relativePaths.count) paths copied.")
        } catch {
            toastMessage = "Paths cannot be copied."
            accessibilityAnnouncer.announce("Paths cannot be copied.")
        }
    }

    @MainActor
    func collectMainListDiagnostics(opening: RepositoryOpeningResult) async {
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: opening.config.repoPath)
            toastMessage = "Diagnostics collected at \(snapshot.snapshotPath)."
        } catch {
            let mapping = await openingFailureMapping(for: error)
            toastMessage = mapping.userMessage
        }
    }
}
