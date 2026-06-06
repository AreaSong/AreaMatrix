@testable import AreaMatrixIOS
import Foundation
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ShareImportModelTests: XCTestCase {
    func testPrepareUsesRecentRepositoryAndCorePrediction() async throws {
        let source = try makeSharedFile(name: "Invoice.pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeShareImportCoreBridge(prediction: .fixture(category: "receipts"))
        let model = makeModel(itemURLs: [source], bridge: bridge)

        await model.prepare()

        let predictions = await bridge.predictionRequestsSnapshot()
        XCTAssertEqual(predictions.map(\.repoPath), ["/tmp/Repo"])
        XCTAssertEqual(predictions.map(\.filename), ["Invoice.pdf"])
        XCTAssertEqual(model.repositoryName, "Recent Repo")
        XCTAssertEqual(model.category, "receipts")
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.canSave)
    }

    func testNoRepositoryDisablesSaveAndOffersMainApp() async throws {
        let source = try makeSharedFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let repoAccess = FakeExtensionRepositoryAccess(resolution: .none)
        let model = makeModel(itemURLs: [source], repositoryAccess: repoAccess)

        await model.prepare()

        XCTAssertEqual(model.error, .noRepository)
        XCTAssertEqual(model.phase, .permissionRequired)
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(model.shouldOfferOpenApp)
    }

    func testSaveSingleReadableItemImportsThroughCoreBridge() async throws {
        let source = try makeSharedFile(name: "Receipt.pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeShareImportCoreBridge(prediction: .fixture(category: "receipts"))
        let queue = FakeSharedContainerImportQueue()
        let model = makeModel(itemURLs: [source], bridge: bridge, queue: queue)

        await model.prepare()
        model.filename = "Receipt 2026.pdf"
        model.updateCategory("finance")
        await model.save()

        let imports = await bridge.importRequestsSnapshot()
        let stagedItems = await queue.immediateStagedItemsSnapshot()
        let removedItems = await queue.removedImmediateItemsSnapshot()
        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports.first?.repoPath, "/tmp/Repo")
        XCTAssertEqual(imports.first?.sourceURL, stagedItems.first?.fileURL)
        XCTAssertEqual(imports.first?.filename, "Receipt 2026.pdf")
        XCTAssertEqual(imports.first?.category, "finance")
        XCTAssertEqual(stagedItems.count, 1)
        XCTAssertEqual(removedItems, stagedItems)
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(model.result, .imported(.fixture(name: "Receipt 2026.pdf", category: "finance")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testConflictFromCoreQueuesItemForMainAppReview() async throws {
        let source = try makeSharedFile(name: "Plan.pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let bridge = FakeShareImportCoreBridge(
            prediction: .fixture(category: "inbox"),
            importErrors: [.conflictNeedsReview("inbox/Plan.pdf")]
        )
        let queue = FakeSharedContainerImportQueue()
        let model = makeModel(itemURLs: [source], bridge: bridge, queue: queue)

        await model.prepare()
        await model.save()

        let queueRequests = await queue.requestsSnapshot()
        let stagedItems = await queue.immediateStagedItemsSnapshot()
        let removedItems = await queue.removedImmediateItemsSnapshot()
        XCTAssertEqual(queueRequests.count, 1)
        XCTAssertEqual(queueRequests.first?.items.map(\.sourceURL), stagedItems.map(\.fileURL))
        XCTAssertEqual(queueRequests.first?.needsConflictReview, true)
        XCTAssertEqual(removedItems, stagedItems)
        XCTAssertEqual(model.phase, .saved)
        XCTAssertTrue(model.shouldOfferOpenApp)
    }

    func testMultipleItemsWithPartialUnreadableQueuesReadableItemsOnly() async throws {
        let first = try makeSharedFile(name: "First.pdf")
        let second = try makeSharedFile(name: "Second.pdf")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-\(UUID()).pdf")
        let items = [
            ShareImportItem(sourceURL: first, sourceApp: "Files"),
            ShareImportItem(sourceURL: second, sourceApp: "Files"),
            ShareImportItem(sourceURL: missing, sourceApp: "Files", isReadable: false)
        ]
        let queue = FakeSharedContainerImportQueue()
        let model = makeModel(items: items, queue: queue)

        await model.prepare()
        XCTAssertEqual(model.objectSummary, "2 of 3 items can be imported")
        await model.save()

        let queueRequests = await queue.requestsSnapshot()
        XCTAssertEqual(queueRequests.count, 1)
        XCTAssertEqual(queueRequests.first?.items.map(\.sourceURL), [first, second])
        XCTAssertEqual(queueRequests.first?.needsConflictReview, false)
        XCTAssertEqual(model.phase, .saved)
    }

    func testSharedContainerQueueWritesMetadataWithoutPayloadContent() async throws {
        let root = try makeTemporaryDirectory()
        let source = try makeSharedFile(name: "Secret.txt", content: "external app payload")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let queue = SharedContainerImportQueue(rootURL: root)
        let request = ShareImportQueueRequest(
            repoPath: "/tmp/Repo",
            category: "inbox",
            items: [ShareImportItem(sourceURL: source, sourceApp: "Files")],
            needsConflictReview: false
        )

        let ticket = try await queue.saveTicket(request: request)

        let ticketURL = root
            .appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent("\(ticket.id).json")
        let metadata = try String(contentsOf: ticketURL)
        XCTAssertFalse(metadata.contains("external app payload"))
        let stagedPath = root.appendingPathComponent(ticket.items[0].stagedRelativePath).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPath))
    }

    func testExtensionItemReaderPreviewsFileProviderPayloadWithoutCopyingToIncoming() async throws {
        let root = try makeTemporaryDirectory()
        let source = try makeSharedFile(name: "Shared.pdf", content: "share sheet bytes")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let extensionItem = NSExtensionItem()
        extensionItem.attributedTitle = NSAttributedString(string: "Files")
        extensionItem.attachments = [provider]
        let reader = ShareImportExtensionItemReader(incomingRoot: root)

        let payload = try await reader.payload(from: [extensionItem])

        XCTAssertEqual(payload.readableItems.count, 1)
        XCTAssertEqual(payload.readableItems.first?.displayName, "Shared.pdf")
        XCTAssertEqual(payload.readableItems.first?.sourceApp, "Files")
        XCTAssertEqual(payload.readableItems.first?.sourceURL, source)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [], [])
    }

    func testSharedContainerQueueStagesPayloadOnlyWhenSaveCreatesTicket() async throws {
        let root = try makeTemporaryDirectory()
        let source = try makeSharedFile(name: "Queued.txt", content: "queued bytes")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let item = ShareImportItem(sourceURL: source, sourceApp: "Files")
        let queue = SharedContainerImportQueue(rootURL: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("payloads").path))
        let ticket = try await queue.saveTicket(request: ShareImportQueueRequest(
            repoPath: "/tmp/Repo",
            category: "inbox",
            items: [item],
            needsConflictReview: false
        ))

        let stagedURL = root.appendingPathComponent(ticket.items[0].stagedRelativePath)
        XCTAssertEqual(try String(contentsOf: stagedURL), "queued bytes")
    }

    func testQueueConsumerImportsDeferredTicketAndDeletesCompletedPayload() async throws {
        let stagedFile = try makeSharedFile(name: "Queued.pdf")
        defer { try? FileManager.default.removeItem(at: stagedFile) }
        let ticket = ShareImportQueueTicket.fixture(
            id: "ticket-1",
            repoPath: "/tmp/Repo",
            category: "receipts",
            item: .fixture(displayName: "Queued.pdf", stagedRelativePath: "payloads/ticket-1/Queued.pdf"),
            needsConflictReview: false
        )
        let queue = FakeSharedContainerTicketQueue(tickets: [ticket], stagedFiles: [
            "payloads/ticket-1/Queued.pdf": stagedFile
        ])
        let bridge = FakeShareImportCoreBridge()
        let consumer = ShareImportQueueConsumer(queue: queue, bridge: bridge)

        let report = await consumer.consumePendingTickets(repoPath: "/tmp/Repo")

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.map(\.repoPath), ["/tmp/Repo"])
        XCTAssertEqual(imports.map(\.filename), ["Queued.pdf"])
        XCTAssertEqual(imports.map(\.category), ["receipts"])
        XCTAssertEqual(imports.map(\.sourceURL), [stagedFile])
        XCTAssertEqual(report.imported.map(\.currentName), ["Queued.pdf"])
        XCTAssertTrue(report.needsReview.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        let completedTicketIDs = await queue.completedTicketIDsSnapshot()
        XCTAssertEqual(completedTicketIDs, ["ticket-1"])
    }

    func testQueueConsumerKeepsNeedsReviewTicketForMainAppConfirmation() async throws {
        let ticket = ShareImportQueueTicket.fixture(
            id: "ticket-review",
            repoPath: "/tmp/Repo",
            category: "inbox",
            item: .fixture(displayName: "Conflict.pdf", stagedRelativePath: "payloads/ticket-review/Conflict.pdf"),
            needsConflictReview: true
        )
        let queue = FakeSharedContainerTicketQueue(tickets: [ticket])
        let bridge = FakeShareImportCoreBridge()
        let consumer = ShareImportQueueConsumer(queue: queue, bridge: bridge)

        let report = await consumer.consumePendingTickets(repoPath: "/tmp/Repo")

        XCTAssertEqual(report.needsReview.map(\.id), ["ticket-review"])
        XCTAssertTrue(report.imported.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        let importRequests = await bridge.importRequestsSnapshot()
        let completedTicketIDs = await queue.completedTicketIDsSnapshot()
        XCTAssertTrue(importRequests.isEmpty)
        XCTAssertTrue(completedTicketIDs.isEmpty)
    }

    func testQueueConsumerKeepsMultiItemTicketForMainAppReview() async throws {
        let ticket = ShareImportQueueTicket(
            id: "ticket-multi",
            repoPath: "/tmp/Repo",
            category: "inbox",
            items: [
                .fixture(displayName: "First.pdf", stagedRelativePath: "payloads/ticket-multi/First.pdf"),
                .fixture(displayName: "Second.pdf", stagedRelativePath: "payloads/ticket-multi/Second.pdf")
            ],
            needsConflictReview: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let queue = FakeSharedContainerTicketQueue(tickets: [ticket])
        let bridge = FakeShareImportCoreBridge()
        let consumer = ShareImportQueueConsumer(queue: queue, bridge: bridge)

        let report = await consumer.consumePendingTickets(repoPath: "/tmp/Repo")
        let importRequests = await bridge.importRequestsSnapshot()
        let completedTicketIDs = await queue.completedTicketIDsSnapshot()

        XCTAssertEqual(report.needsReview.map(\.id), ["ticket-multi"])
        XCTAssertTrue(importRequests.isEmpty)
        XCTAssertTrue(completedTicketIDs.isEmpty)
    }

    private func makeModel(
        itemURLs: [URL],
        bridge: any ShareImportCoreBridge = FakeShareImportCoreBridge(),
        repositoryAccess: any ExtensionRepositoryAccessing = FakeExtensionRepositoryAccess(),
        queue: any SharedContainerImportQueuing = FakeSharedContainerImportQueue()
    ) -> ShareImportModel {
        makeModel(
            items: itemURLs.map { ShareImportItem(sourceURL: $0, sourceApp: "Files") },
            bridge: bridge,
            repositoryAccess: repositoryAccess,
            queue: queue
        )
    }

    private func makeModel(
        items: [ShareImportItem],
        bridge: any ShareImportCoreBridge = FakeShareImportCoreBridge(),
        repositoryAccess: any ExtensionRepositoryAccessing = FakeExtensionRepositoryAccess(),
        queue: any SharedContainerImportQueuing = FakeSharedContainerImportQueue()
    ) -> ShareImportModel {
        ShareImportModel(
            payload: ShareImportPayload(items: items),
            bridge: bridge,
            repositoryAccess: repositoryAccess,
            queue: queue
        )
    }

    private func makeSharedFile(name: String? = nil, content: String = "shared bytes") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name ?? "Shared-\(UUID().uuidString).pdf")
        try Data(content.utf8).write(to: url)
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixShareImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

actor FakeShareImportCoreBridge: ShareImportCoreBridge {
    typealias PredictionRequest = (repoPath: String, filename: String)

    private let prediction: ShareImportCategoryPrediction
    private var importErrors: [ShareImportError]
    private var predictionRequests: [PredictionRequest] = []
    private var importRequests: [ShareImportCoreRequest] = []

    init(
        prediction: ShareImportCategoryPrediction = .fixture(category: "inbox"),
        importErrors: [ShareImportError] = []
    ) {
        self.prediction = prediction
        self.importErrors = importErrors
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ShareImportCategoryPrediction {
        predictionRequests.append((repoPath, filename))
        return prediction
    }

    func importSharedItem(request: ShareImportCoreRequest) async throws -> MobileLibraryFile {
        importRequests.append(request)
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
    private var accessedURLs: [URL] = []

    init(resolution: ExtensionRepositoryResolution = .available(.fixture(), URL(fileURLWithPath: "/tmp/Repo"))) {
        self.resolution = resolution
    }

    func defaultRepository() async -> ExtensionRepositoryResolution {
        resolution
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        accessedURLs.append(url)
        return RepositoryScopedAccess(url: url) {}
    }

    func accessedURLsSnapshot() -> [URL] {
        accessedURLs
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

private extension ShareImportCategoryPrediction {
    static func fixture(category: String) -> ShareImportCategoryPrediction {
        ShareImportCategoryPrediction(category: category, suggestedName: "", confidence: 0.9)
    }
}

private extension RecentRepository {
    static func fixture() -> RecentRepository {
        RecentRepository(
            displayName: "Recent Repo",
            pathDisplay: "/tmp/Repo",
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            accessStatus: .available
        )
    }
}

private extension MobileLibraryFile {
    static func fixture(name: String, category: String) -> MobileLibraryFile {
        MobileLibraryFile(
            id: 1, path: "\(category)/\(name)", originalName: name, currentName: name,
            category: category, sizeBytes: 10, hashSha256: "hash-1",
            storageMode: "Copied", origin: "Imported", sourcePath: nil, availability: .available,
            importedAt: 1, updatedAt: 1
        )
    }
}

private extension ShareImportQueueTicket {
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

private extension ShareImportQueuedItem {
    static func fixture(displayName: String, stagedRelativePath: String) -> ShareImportQueuedItem {
        ShareImportQueuedItem(
            displayName: displayName, stagedRelativePath: stagedRelativePath, sourceApp: "Files", sizeBytes: 10
        )
    }
}
