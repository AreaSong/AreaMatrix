import Foundation

protocol RepositoryAccessServicing: Sendable {
    func recentRepositories() async -> [RecentRepository]
    func isICloudDriveAvailable() async -> Bool
    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess
    func persistBookmark(for url: URL, lastOpenedAt: Date) async throws -> RepositoryBookmark
    func resolveBookmark(for recent: RecentRepository) async throws -> URL
}

struct RepositoryBookmark: Equatable, Sendable {
    var url: URL
    var displayName: String
    var pathDisplay: String
    var lastOpenedAt: Date
}

struct RecentRepository: Identifiable, Equatable, Sendable {
    enum AccessStatus: Equatable, Sendable {
        case available
        case expired
    }

    var id: String { pathDisplay }
    var displayName: String
    var pathDisplay: String
    var lastOpenedAt: Date
    var accessStatus: AccessStatus
}

struct RepositoryScopedAccess: Sendable {
    let url: URL
    private let stopHandler: @Sendable () -> Void

    init(url: URL, stopHandler: @escaping @Sendable () -> Void) {
        self.url = url
        self.stopHandler = stopHandler
    }

    func stop() {
        stopHandler()
    }
}

actor SecurityScopedRepositoryAccessService: RepositoryAccessServicing {
    private struct StoredBookmark: Codable {
        var data: Data
        var displayName: String
        var pathDisplay: String
        var lastOpenedAt: Date
    }

    private let defaults: UserDefaults
    private let key = "areamatrix.ios.recentRepositories"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recentRepositories() async -> [RecentRepository] {
        storedBookmarks().map { stored in
            RecentRepository(
                displayName: stored.displayName,
                pathDisplay: stored.pathDisplay,
                lastOpenedAt: stored.lastOpenedAt,
                accessStatus: resolvedURL(from: stored) == nil ? .expired : .available
            )
        }
    }

    func isICloudDriveAvailable() async -> Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        let didStart = url.startAccessingSecurityScopedResource()
        guard didStart || FileManager.default.isReadableFile(atPath: url.path) else {
            throw MobileRepositoryConnectionError.permissionDenied(url.path)
        }
        return RepositoryScopedAccess(url: url) {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    func persistBookmark(for url: URL, lastOpenedAt: Date) async throws -> RepositoryBookmark {
        let bookmark = try makeBookmark(for: url, lastOpenedAt: lastOpenedAt)
        var stored = storedBookmarks().filter { $0.pathDisplay != bookmark.pathDisplay }
        stored.insert(try storedBookmark(from: bookmark), at: 0)
        saveStoredBookmarks(Array(stored.prefix(5)))
        return bookmark
    }

    func resolveBookmark(for recent: RecentRepository) async throws -> URL {
        guard let stored = storedBookmarks().first(where: { $0.pathDisplay == recent.pathDisplay }),
              let url = resolvedURL(from: stored) else {
            throw MobileRepositoryConnectionError.accessExpired(recent.pathDisplay)
        }
        return url
    }

    private func makeBookmark(for url: URL, lastOpenedAt: Date) throws -> RepositoryBookmark {
        _ = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return RepositoryBookmark(
            url: url,
            displayName: url.lastPathComponent.isEmpty ? "Repository" : url.lastPathComponent,
            pathDisplay: url.path,
            lastOpenedAt: lastOpenedAt
        )
    }

    private func storedBookmark(from bookmark: RepositoryBookmark) throws -> StoredBookmark {
        StoredBookmark(
            data: try bookmark.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ),
            displayName: bookmark.displayName,
            pathDisplay: bookmark.pathDisplay,
            lastOpenedAt: bookmark.lastOpenedAt
        )
    }

    private func resolvedURL(from stored: StoredBookmark) -> URL? {
        var stale = ObjCBool(false)
        guard let url = try? NSURL(
            resolvingBookmarkData: stored.data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        guard !stale.boolValue else { return nil }
        return url as URL
    }

    private func storedBookmarks() -> [StoredBookmark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StoredBookmark].self, from: data)) ?? []
    }

    private func saveStoredBookmarks(_ bookmarks: [StoredBookmark]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: key)
    }
}
