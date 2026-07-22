import Foundation

extension OnboardingModel {
    @MainActor
    func openLearnMore() {
        do {
            try helpOpener.openWelcomeHelp()
        } catch {
            toastMessage = L10n.string("Learn more is unavailable right now.")
        }
    }

    @MainActor
    func showMainListFileInFinder(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileRevealer.revealFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.string("File cannot be shown in Finder.")
        }
    }

    @MainActor
    func openMainListFile(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileOpener.openFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.string("File cannot be opened.")
        }
    }

    @MainActor
    func copyMainListPath(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try pathCopier.copyPath(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = L10n.string("Path copied.")
            accessibilityAnnouncer.announce("Path copied.")
        } catch {
            toastMessage = L10n.string("Path cannot be copied.")
            accessibilityAnnouncer.announce("Path cannot be copied.")
        }
    }

    @MainActor
    func copyMainListPaths(opening: RepositoryOpeningResult, relativePaths: [String]) {
        do {
            try pathCopier.copyPaths(repoPath: opening.config.repoPath, relativePaths: relativePaths)
            let message = L10n.plural("main-list.paths-copied", count: relativePaths.count)
            toastMessage = message
            accessibilityAnnouncer.announce(message)
        } catch {
            toastMessage = L10n.string("Paths cannot be copied.")
            accessibilityAnnouncer.announce("Paths cannot be copied.")
        }
    }

    @MainActor
    func collectMainListDiagnostics(opening: RepositoryOpeningResult) async {
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: opening.config.repoPath)
            toastMessage = L10n.format("mainList.diagnosticsCollected", snapshot.snapshotPath)
        } catch {
            let mapping = await openingFailureMapping(for: error)
            toastMessage = mapping.userMessage
        }
    }
}
