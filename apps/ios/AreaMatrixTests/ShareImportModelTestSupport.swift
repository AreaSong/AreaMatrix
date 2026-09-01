@testable import AreaMatrixIOS
import Foundation

actor ShareImportOperationGate {
    private var isStarted = false
    private var isFinished = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        isStarted = true
        resume(&startContinuations)
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            finishContinuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func finish() {
        isFinished = true
        resume(&finishContinuations)
    }

    private func resume(_ continuations: inout [CheckedContinuation<Void, Never>]) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor FakeShareImportCoreBridge: ShareImportCoreBridge {
    typealias PredictionRequest = (repoPath: String, filename: String)

    private let prediction: ShareImportCategoryPrediction
    private let importGate: ShareImportOperationGate?
    private var importErrors: [ShareImportError]
    private var predictionRequests: [PredictionRequest] = []
    private var importRequests: [ShareImportCoreRequest] = []

    init(
        prediction: ShareImportCategoryPrediction = .fixture(category: "inbox"),
        importErrors: [ShareImportError] = [],
        importGate: ShareImportOperationGate? = nil
    ) {
        self.prediction = prediction
        self.importErrors = importErrors
        self.importGate = importGate
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ShareImportCategoryPrediction {
        predictionRequests.append((repoPath, filename))
        return prediction
    }

    func importSharedItem(request: ShareImportCoreRequest) async throws -> MobileLibraryFile {
        importRequests.append(request)
        if let importGate {
            await importGate.suspend()
        }
        if !importErrors.isEmpty {
            throw importErrors.removeFirst()
        }
        return .fixture(name: request.filename, category: request.category)
    }

    func predictionRequestsSnapshot() -> [PredictionRequest] {
        predictionRequests
    }

    func importRequestsSnapshot() -> [ShareImportCoreRequest] {
        importRequests
    }
}

actor FakeExtensionRepositoryAccess: ExtensionRepositoryAccessing {
    private let resolution: ExtensionRepositoryResolution
    private let accessProbe: ShareImportAccessProbe?
    private var accessedURLs: [URL] = []

    init(
        resolution: ExtensionRepositoryResolution = .available(.fixture(), URL(fileURLWithPath: "/tmp/Repo")),
        accessProbe: ShareImportAccessProbe? = nil
    ) {
        self.resolution = resolution
        self.accessProbe = accessProbe
    }

    func defaultRepository() async -> ExtensionRepositoryResolution {
        resolution
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        accessedURLs.append(url)
        accessProbe?.recordStart()
        return RepositoryScopedAccess(url: url) { [accessProbe] in
            accessProbe?.recordStop()
        }
    }

    func accessedURLsSnapshot() -> [URL] {
        accessedURLs
    }
}

final class ShareImportAccessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    func recordStart() {
        lock.withLock { starts += 1 }
    }

    func recordStop() {
        lock.withLock { stops += 1 }
    }

    var counts: (starts: Int, stops: Int) {
        lock.withLock { (starts, stops) }
    }
}

actor GatedSharedContainerImportQueue: SharedContainerImportQueuing {
    private let queue: SharedContainerImportQueue
    private let ticketReturnGate: ShareImportOperationGate

    init(rootURL: URL, ticketReturnGate: ShareImportOperationGate) {
        queue = SharedContainerImportQueue(rootURL: rootURL)
        self.ticketReturnGate = ticketReturnGate
    }

    func saveTicket(request: ShareImportQueueRequest) async throws -> ShareImportQueueTicket {
        let ticket = try await queue.saveTicket(request: request)
        await ticketReturnGate.suspend()
        return ticket
    }

    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem {
        try await queue.stageItemForImmediateImport(item)
    }

    func removeImmediateStagedItem(_ item: ShareImportImmediateStagedItem) async throws {
        try await queue.removeImmediateStagedItem(item)
    }

    func pendingTickets(forRepoPath repoPath: String) async throws -> [ShareImportQueueTicket] {
        try await queue.pendingTickets(forRepoPath: repoPath)
    }
}

actor FakeSharedContainerImportQueue: SharedContainerImportQueuing {
    private var requests: [ShareImportQueueRequest] = []
    private var immediateItems: [ShareImportImmediateStagedItem] = []
    private var removedItems: [ShareImportImmediateStagedItem] = []

    func saveTicket(request: ShareImportQueueRequest) async throws -> ShareImportQueueTicket {
        requests.append(request)
        return ShareImportQueueTicket(
            id: "ticket-\(requests.count)",
            repoPath: request.repoPath,
            category: request.category,
            items: request.items.map {
                ShareImportQueuedItem(
                    displayName: $0.displayName,
                    stagedRelativePath: "payloads/ticket-\(requests.count)/\($0.safeFilename)",
                    sourceApp: $0.sourceApp,
                    sizeBytes: $0.sizeBytes
                )
            },
            needsConflictReview: request.needsConflictReview,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem {
        let stagedItem = ShareImportImmediateStagedItem(
            fileURL: URL(fileURLWithPath: "/tmp/Immediate-\(immediateItems.count + 1)-\(item.safeFilename)")
        )
        immediateItems.append(stagedItem)
        return stagedItem
    }

    func removeImmediateStagedItem(_ item: ShareImportImmediateStagedItem) async throws {
        removedItems.append(item)
    }

    func requestsSnapshot() -> [ShareImportQueueRequest] {
        requests
    }

    func immediateStagedItemsSnapshot() -> [ShareImportImmediateStagedItem] {
        immediateItems
    }

    func removedImmediateItemsSnapshot() -> [ShareImportImmediateStagedItem] {
        removedItems
    }
}

actor FakeSharedContainerTicketQueue: SharedContainerImportTicketConsuming {
    private let tickets: [ShareImportQueueTicket]
    private let stagedFiles: [String: URL]
    private var completedTicketIDs: [String] = []

    init(tickets: [ShareImportQueueTicket], stagedFiles: [String: URL] = [:]) {
        self.tickets = tickets
        self.stagedFiles = stagedFiles
    }

    func pendingTickets(forRepoPath repoPath: String) async throws -> [ShareImportQueueTicket] {
        tickets.filter { $0.repoPath == repoPath }
    }

    func stagedFileURL(for item: ShareImportQueuedItem) async throws -> URL {
        guard let url = stagedFiles[item.stagedRelativePath] else {
            throw ShareImportError.permissionDenied(item.stagedRelativePath)
        }
        return url
    }

    func markTicketCompleted(_ ticket: ShareImportQueueTicket) async throws {
        completedTicketIDs.append(ticket.id)
    }

    func completedTicketIDsSnapshot() -> [String] {
        completedTicketIDs
    }
}

extension ShareImportCategoryPrediction {
    static func fixture(category: String) -> ShareImportCategoryPrediction {
        ShareImportCategoryPrediction(category: category, suggestedName: "", confidence: 0.9)
    }
}

extension RecentRepository {
    static func fixture() -> RecentRepository {
        RecentRepository(
            displayName: "Recent Repo",
            pathDisplay: "/tmp/Repo",
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            accessStatus: .available
        )
    }
}

extension MobileLibraryFile {
    static func fixture(name: String, category: String) -> MobileLibraryFile {
        MobileLibraryFile(
            id: 1, path: "\(category)/\(name)", originalName: name, currentName: name,
            category: category, sizeBytes: 10, hashSha256: "hash-1",
            storageMode: "Copied", origin: "Imported", sourcePath: nil, availability: .available,
            importedAt: 1, updatedAt: 1
        )
    }
}

extension ShareImportQueueTicket {
    static func fixture(
        id: String,
        repoPath: String,
        category: String,
        item: ShareImportQueuedItem,
        needsConflictReview: Bool
    ) -> ShareImportQueueTicket {
        ShareImportQueueTicket(
            id: id,
            repoPath: repoPath,
            category: category,
            items: [item],
            needsConflictReview: needsConflictReview,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}

extension ShareImportQueuedItem {
    static func fixture(displayName: String, stagedRelativePath: String) -> ShareImportQueuedItem {
        ShareImportQueuedItem(
            displayName: displayName, stagedRelativePath: stagedRelativePath, sourceApp: "Files", sizeBytes: 10
        )
    }
}
