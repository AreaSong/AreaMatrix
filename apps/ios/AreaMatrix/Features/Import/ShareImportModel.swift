import Foundation

enum ShareImportItemKind: String, Equatable, Sendable {
    case file
    case url
}

final class ShareImportDeferredFileProvider: @unchecked Sendable {
    let id = UUID().uuidString
    let itemProvider: NSItemProvider
    let typeIdentifier: String

    init(itemProvider: NSItemProvider, typeIdentifier: String) {
        self.itemProvider = itemProvider
        self.typeIdentifier = typeIdentifier
    }
}

struct ShareImportItem: Equatable, Identifiable, Sendable {
    var id: String
    var sourceURL: URL
    var displayName: String
    var sourceApp: String
    var sizeBytes: Int64?
    var kind: ShareImportItemKind
    var isReadable: Bool
    var deferredProvider: ShareImportDeferredFileProvider?

    init(
        id: String = UUID().uuidString,
        sourceURL: URL,
        displayName: String? = nil,
        sourceApp: String,
        sizeBytes: Int64? = nil,
        kind: ShareImportItemKind = .file,
        isReadable: Bool? = nil,
        deferredProvider: ShareImportDeferredFileProvider? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName ?? sourceURL.lastPathComponent
        self.sourceApp = sourceApp
        self.sizeBytes = sizeBytes ?? Self.fileSize(for: sourceURL)
        self.kind = kind
        self.isReadable = isReadable ?? FileManager.default.isReadableFile(atPath: sourceURL.path)
        self.deferredProvider = deferredProvider
    }

    var safeFilename: String {
        Self.safeFilename(displayName)
    }

    static func == (lhs: ShareImportItem, rhs: ShareImportItem) -> Bool {
        lhs.id == rhs.id
            && lhs.sourceURL == rhs.sourceURL
            && lhs.displayName == rhs.displayName
            && lhs.sourceApp == rhs.sourceApp
            && lhs.sizeBytes == rhs.sizeBytes
            && lhs.kind == rhs.kind
            && lhs.isReadable == rhs.isReadable
            && lhs.deferredProvider?.id == rhs.deferredProvider?.id
    }

    static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Shared Item" : trimmed
    }

    private static func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }
}

struct ShareImportPayload: Equatable, Sendable {
    var items: [ShareImportItem]

    var readableItems: [ShareImportItem] {
        items.filter(\.isReadable)
    }

    var sourceApp: String {
        readableItems.first?.sourceApp ?? items.first?.sourceApp ?? "Share Sheet"
    }

    var totalReadableSize: Int64? {
        let sizes = readableItems.compactMap(\.sizeBytes)
        guard sizes.count == readableItems.count else { return nil }
        return sizes.reduce(0, +)
    }
}

enum ExtensionRepositoryResolution: Equatable, Sendable {
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

enum ShareImportPhase: Equatable {
    case reading
    case ready
    case saving
    case saved
    case empty
    case failed
    case permissionRequired
}

enum ShareImportResult: Equatable {
    case imported(MobileLibraryFile)
    case queued(ShareImportQueueTicket)
}

@MainActor
final class ShareImportModel: ObservableObject {
    @Published private(set) var phase: ShareImportPhase = .reading
    @Published private(set) var error: ShareImportError?
    @Published private(set) var warning: String?
    @Published private(set) var result: ShareImportResult?
    @Published private(set) var repositoryName: String = "Repository"
    @Published var category: String = "inbox"
    @Published var filename: String = ""

    let payload: ShareImportPayload

    private let bridge: any ShareImportCoreBridge
    private let repositoryAccess: any ExtensionRepositoryAccessing
    private let queue: any SharedContainerImportQueuing
    private var repoURL: URL?
    private var repoPath: String = ""

    init(
        payload: ShareImportPayload,
        bridge: any ShareImportCoreBridge,
        repositoryAccess: any ExtensionRepositoryAccessing = ExtensionRepositoryAccess(),
        queue: any SharedContainerImportQueuing = SharedContainerImportQueue()
    ) {
        self.payload = payload
        self.bridge = bridge
        self.repositoryAccess = repositoryAccess
        self.queue = queue
        filename = Self.defaultFilename(for: payload.readableItems)
    }

    var canSave: Bool {
        phase == .ready
            && !payload.readableItems.isEmpty
            && repoURL != nil
            && filenameValidation == nil
            && error == nil
    }

    var allowsFilenameEditing: Bool {
        payload.readableItems.count == 1
    }

    var filenameValidation: String? {
        allowsFilenameEditing && filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "File name is required."
            : nil
    }

    var saveButtonTitle: String {
        phase == .saving ? "Saving..." : "Save"
    }

    var statusText: String {
        switch phase {
        case .reading:
            "Reading shared item..."
        case .ready:
            "Ready to save"
        case .saving:
            "Saving queue item..."
        case .saved:
            resultQueued ? "Queued for AreaMatrix" : "Saved to AreaMatrix"
        case .empty:
            "No supported items to import."
        case .failed:
            "Share import failed"
        case .permissionRequired:
            "Open AreaMatrix to connect a repository"
        }
    }

    var objectSummary: String {
        let readable = payload.readableItems.count
        if readable == 0 {
            return "No supported items to import."
        }
        if readable == 1, let item = payload.readableItems.first {
            return "\(item.displayName) from \(item.sourceApp)"
        }
        if readable < payload.items.count {
            return "\(readable) of \(payload.items.count) items can be imported"
        }
        return "\(readable) items from \(payload.sourceApp)"
    }

    var totalSizeText: String {
        guard let size = payload.totalReadableSize else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var shouldOfferOpenApp: Bool {
        if case .queued = result {
            return true
        }
        return error?.shouldOpenMainApp ?? false
    }

    func prepare() async {
        guard phase == .reading else { return }
        guard !payload.readableItems.isEmpty else {
            error = .unsupportedItem("No supported items to import.")
            phase = .empty
            return
        }
        switch await repositoryAccess.defaultRepository() {
        case let .available(repo, url):
            repositoryName = repo.displayName
            repoURL = url
            repoPath = url.path
            await applyPrediction()
        case .none:
            error = .noRepository
            phase = .permissionRequired
        case let .expired(repo):
            repositoryName = repo.displayName
            error = .permissionExpired(repo.pathDisplay)
            phase = .permissionRequired
        }
    }

    func save() async {
        guard canSave, let repoURL else { return }
        phase = .saving
        error = nil
        do {
            let access = try await repositoryAccess.beginAccessing(repoURL)
            defer { access.stop() }
            if payload.readableItems.count == 1 {
                try await importSingleItemOrQueueConflict()
            } else {
                result = .queued(try await makeQueueTicket(needsConflictReview: false))
            }
            phase = .saved
        } catch {
            self.error = ShareImportError.map(error)
            phase = .failed
        }
    }

    func updateCategory(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        category = trimmed.isEmpty ? "inbox" : trimmed
    }

    private var resultQueued: Bool {
        if case .queued = result {
            return true
        }
        return false
    }

    private func applyPrediction() async {
        do {
            let prediction = try await bridge.predictCategory(repoPath: repoPath, filename: filename)
            category = prediction.category.isEmpty ? "inbox" : prediction.category
            if allowsFilenameEditing && !prediction.suggestedName.isEmpty {
                filename = ShareImportItem.safeFilename(prediction.suggestedName)
            }
            phase = .ready
        } catch {
            let mapped = ShareImportError.map(error)
            if mapped.blocksPreparation {
                self.error = mapped
                phase = .failed
                return
            }
            warning = mapped.message
            category = "inbox"
            phase = .ready
        }
    }

    private func importSingleItemOrQueueConflict() async throws {
        let item = try singleReadableItem()
        let stagedItem = try await queue.stageItemForImmediateImport(item)
        do {
            let importedFile = try await bridge.importSharedItem(
                request: makeCoreRequest(sourceURL: stagedItem.fileURL)
            )
            result = .imported(importedFile)
            await removeImmediateStaging(stagedItem)
        } catch {
            let mapped = ShareImportError.map(error)
            guard case .conflictNeedsReview = mapped else {
                await removeImmediateStaging(stagedItem)
                throw mapped
            }
            do {
                result = .queued(try await makeQueueTicket(
                    needsConflictReview: true,
                    items: [stagedQueueItem(from: item, stagedURL: stagedItem.fileURL)]
                ))
                await removeImmediateStaging(stagedItem)
            } catch {
                await removeImmediateStaging(stagedItem)
                throw error
            }
        }
    }

    private func singleReadableItem() throws -> ShareImportItem {
        guard let item = payload.readableItems.first else {
            throw ShareImportError.unsupportedItem("No supported items to import.")
        }
        return item
    }

    private func makeCoreRequest(sourceURL: URL) -> ShareImportCoreRequest {
        return ShareImportCoreRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            filename: ShareImportItem.safeFilename(filename),
            category: normalizedCategory
        )
    }

    private func removeImmediateStaging(_ item: ShareImportImmediateStagedItem) async {
        do {
            try await queue.removeImmediateStagedItem(item)
        } catch {
            warning = ShareImportError.map(error).message
        }
    }

    private func makeQueueTicket(
        needsConflictReview: Bool,
        items: [ShareImportItem]? = nil
    ) async throws -> ShareImportQueueTicket {
        try await queue.saveTicket(request: ShareImportQueueRequest(
            repoPath: repoPath,
            category: normalizedCategory,
            items: items ?? payload.readableItems,
            needsConflictReview: needsConflictReview
        ))
    }

    private func stagedQueueItem(from item: ShareImportItem, stagedURL: URL) -> ShareImportItem {
        ShareImportItem(
            sourceURL: stagedURL,
            displayName: item.displayName,
            sourceApp: item.sourceApp,
            sizeBytes: item.sizeBytes,
            kind: .file,
            isReadable: true
        )
    }

    private var normalizedCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "inbox" : trimmed
    }

    private static func defaultFilename(for items: [ShareImportItem]) -> String {
        guard let first = items.first else { return "" }
        if items.count == 1 {
            return first.safeFilename
        }
        return "\(items.count) shared items"
    }
}
