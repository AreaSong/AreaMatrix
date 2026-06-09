import Foundation

extension ConnectRepositoryModel {
    func refreshRepositoryInitConfirmation(_ candidate: MobileRepositoryCandidate) async {
        await refreshRepositoryInitCandidate(candidate) { _ in }
    }

    func refreshRepositoryAdoptConfirmation(_ candidate: MobileRepositoryCandidate) async {
        await refreshRepositoryAdoptCandidate(candidate) { _ in }
    }

    func createRepository(from candidate: MobileRepositoryCandidate) async {
        await refreshRepositoryInitCandidate(candidate) { updatedCandidate in
            try await createValidatedEmptyRepository(from: updatedCandidate)
        }
    }

    func adoptRepository(from candidate: MobileRepositoryCandidate) async {
        await refreshRepositoryAdoptCandidate(candidate) { updatedCandidate in
            try await adoptValidatedExistingRepository(from: updatedCandidate)
        }
    }

    private func refreshRepositoryInitCandidate(
        _ candidate: MobileRepositoryCandidate,
        afterRefresh: (MobileRepositoryCandidate) async throws -> Void
    ) async {
        await refreshRepositoryCandidate(
            candidate,
            makeRoute: { .repositoryInitConfirm($0) },
            isCurrentRoute: Self.isRepositoryInitRoute,
            afterRefresh: afterRefresh
        )
    }

    private func refreshRepositoryAdoptCandidate(
        _ candidate: MobileRepositoryCandidate,
        afterRefresh: (MobileRepositoryCandidate) async throws -> Void
    ) async {
        await refreshRepositoryCandidate(
            candidate,
            makeRoute: { .repositoryAdoptConfirm($0) },
            isCurrentRoute: Self.isRepositoryAdoptRoute,
            afterRefresh: afterRefresh
        )
    }

    private func refreshRepositoryCandidate(
        _ candidate: MobileRepositoryCandidate,
        makeRoute: (MobileRepositoryCandidate) -> MobileRepositoryConnectionRoute,
        isCurrentRoute: (MobileRepositoryConnectionRoute?) -> Bool,
        afterRefresh: (MobileRepositoryCandidate) async throws -> Void
    ) async {
        guard isCurrentRoute(route) else { return }
        beginCheckingRepositoryCandidate(candidate, route: makeRoute(candidate))
        do {
            let scopedAccess = try await accessService.beginAccessing(candidate.bookmark.url)
            defer { scopedAccess.stop() }
            let refreshed = try await bridge.validateRepoPath(repoPath: candidate.validation.repoPath)
            let updatedCandidate = MobileRepositoryCandidate(validation: refreshed, bookmark: candidate.bookmark)
            applyRefreshedRepositoryCandidate(updatedCandidate, route: makeRoute(updatedCandidate))
            try await afterRefresh(updatedCandidate)
        } catch {
            applyFailure(Self.connectionError(from: error))
            restoreRepositoryConfirmationRoute(makeRoute(candidate))
        }
    }

    private func createValidatedEmptyRepository(from candidate: MobileRepositoryCandidate) async throws {
        guard Self.canCreateEmptyRepository(from: candidate.validation) else {
            applyFailure(.invalidRepository(candidate.validation.repoPath))
            restoreRepositoryConfirmationRoute(.repositoryInitConfirm(candidate))
            return
        }
        beginCreatingRepository(candidate, route: .repositoryInitConfirm(candidate))
        try await bridge.initializeEmptyRepository(repoPath: candidate.validation.repoPath)
        let initialized = try await bridge.validateRepoPath(repoPath: candidate.validation.repoPath)
        guard initialized.isInitialized else {
            applyFailure(.invalidRepository(initialized.repoPath))
            restoreRepositoryConfirmationRoute(.repositoryInitConfirm(MobileRepositoryCandidate(
                validation: initialized,
                bookmark: candidate.bookmark
            )))
            return
        }
        recordLatestValidation(initialized)
        let bookmark = try await accessService.persistBookmark(for: candidate.bookmark.url, lastOpenedAt: now())
        try await openCreatedRepository(validation: initialized, bookmark: bookmark)
    }

    private func adoptValidatedExistingRepository(from candidate: MobileRepositoryCandidate) async throws {
        guard Self.canAdoptExistingRepository(from: candidate.validation) else {
            applyFailure(.invalidRepository(candidate.validation.repoPath))
            restoreRepositoryConfirmationRoute(.repositoryAdoptConfirm(candidate))
            return
        }
        beginCreatingRepository(candidate, route: .repositoryAdoptConfirm(candidate))
        try await bridge.adoptExistingRepository(repoPath: candidate.validation.repoPath)
        let initialized = try await bridge.validateRepoPath(repoPath: candidate.validation.repoPath)
        guard initialized.isInitialized else {
            applyFailure(.invalidRepository(initialized.repoPath))
            restoreRepositoryConfirmationRoute(.repositoryAdoptConfirm(MobileRepositoryCandidate(
                validation: initialized,
                bookmark: candidate.bookmark
            )))
            return
        }
        recordLatestValidation(initialized)
        let bookmark = try await accessService.persistBookmark(for: candidate.bookmark.url, lastOpenedAt: now())
        try await openCreatedRepository(validation: initialized, bookmark: bookmark)
    }

    private func beginCheckingRepositoryCandidate(
        _ candidate: MobileRepositoryCandidate,
        route: MobileRepositoryConnectionRoute
    ) {
        beginRepositoryConfirmation(candidate, route: route, state: .checking(candidate.validation.repoPath))
    }

    private func beginCreatingRepository(
        _ candidate: MobileRepositoryCandidate,
        route: MobileRepositoryConnectionRoute
    ) {
        beginRepositoryConfirmation(candidate, route: route, state: .creating(candidate.validation.repoPath))
    }

    private static func canCreateEmptyRepository(from validation: MobileRepositoryValidation) -> Bool {
        validation.recommendedMode == .createEmpty
            && validation.isWritable
            && (!validation.exists || (validation.isDirectory && validation.isReadable && validation.isEmpty))
            && !validation.isInitialized
            && !validation.isInsideAreaMatrix
    }

    private static func canAdoptExistingRepository(from validation: MobileRepositoryValidation) -> Bool {
        validation.recommendedMode == .adoptExisting
            && validation.exists
            && validation.isDirectory
            && validation.isReadable
            && validation.isWritable
            && !validation.isEmpty
            && !validation.isInitialized
            && !validation.isInsideAreaMatrix
            && !validation.hasUnfinishedScanSession
    }

    private static func isRepositoryInitRoute(_ route: MobileRepositoryConnectionRoute?) -> Bool {
        if case .repositoryInitConfirm = route { return true }
        return false
    }

    private static func isRepositoryAdoptRoute(_ route: MobileRepositoryConnectionRoute?) -> Bool {
        if case .repositoryAdoptConfirm = route { return true }
        return false
    }
}
