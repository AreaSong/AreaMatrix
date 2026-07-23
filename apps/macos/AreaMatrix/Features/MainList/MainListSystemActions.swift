import Foundation

extension OnboardingModel {
    @MainActor
    func openLearnMore() {
        do {
            try helpOpener.openWelcomeHelp()
        } catch {
            toastMessage = L10n.message("Learn more is unavailable right now.")
        }
    }

    @MainActor
    func showMainListFileInFinder(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileRevealer.revealFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.message("File cannot be shown in Finder.")
        }
    }

    @MainActor
    func openMainListFile(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileOpener.openFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.message("File cannot be opened.")
        }
    }

    @MainActor
    func copyMainListPath(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try pathCopier.copyPath(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = L10n.message("Path copied.")
            accessibilityAnnouncer.announce(L10n.message("Path copied."))
        } catch {
            toastMessage = L10n.message("Path cannot be copied.")
            accessibilityAnnouncer.announce(L10n.message("Path cannot be copied."))
        }
    }

    @MainActor
    func copyMainListPaths(opening: RepositoryOpeningResult, relativePaths: [String]) {
        do {
            try pathCopier.copyPaths(repoPath: opening.config.repoPath, relativePaths: relativePaths)
            toastMessage = L10n.pluralMessage("main-list.paths-copied", count: relativePaths.count)
            accessibilityAnnouncer.announce(L10n.pluralMessage(
                "main-list.paths-copied",
                count: relativePaths.count
            ))
        } catch {
            toastMessage = L10n.message("Paths cannot be copied.")
            accessibilityAnnouncer.announce(L10n.message("Paths cannot be copied."))
        }
    }

    @MainActor
    func collectMainListDiagnostics(opening: RepositoryOpeningResult) async {
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: opening.config.repoPath)
            toastMessage = L10n.message(
                "mainList.diagnosticsCollected",
                arguments: [.string(snapshot.snapshotPath)]
            )
        } catch {
            let mapping = await openingFailureMapping(for: error)
            toastMessage = mapping.userMessageDescriptor
        }
    }
}
