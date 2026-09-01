import Foundation

enum ExtensionRepositoryResolution: Equatable {
    case available(RecentRepository, URL)
    case none
    case expired(RecentRepository)
}

protocol ExtensionRepositoryAccessing: Sendable {
    func defaultRepository() async -> ExtensionRepositoryResolution
    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess
}

actor ExtensionRepositoryAccess: ExtensionRepositoryAccessing {
    private let service: any RepositoryAccessServicing

    init(service: any RepositoryAccessServicing = SecurityScopedRepositoryAccessService()) {
        self.service = service
    }

    func defaultRepository() async -> ExtensionRepositoryResolution {
        guard let recent = await service.recentRepositories().first else {
            return .none
        }
        guard recent.accessStatus == .available else {
            return .expired(recent)
        }
        do {
            return try await .available(recent, service.resolveBookmark(for: recent))
        } catch {
            return .expired(recent)
        }
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        try await service.beginAccessing(url)
    }
}
