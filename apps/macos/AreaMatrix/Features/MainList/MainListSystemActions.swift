import Foundation

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
