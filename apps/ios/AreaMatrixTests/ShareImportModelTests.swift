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
        try await waitForSave(model)

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
        try await waitForSave(model)

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
        try await waitForSave(model)

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
        provider.suggestedName = "Shared.pdf"
        let extensionItem = NSExtensionItem()
        extensionItem.attributedTitle = NSAttributedString(string: "Files")
        extensionItem.attachments = [provider]
        let reader = ShareImportExtensionItemReader(incomingRoot: root)

        let payload = try await reader.payload(from: [extensionItem])

        XCTAssertEqual(payload.readableItems.count, 1)
        XCTAssertEqual(payload.readableItems.first?.displayName, "Shared.pdf")
        XCTAssertEqual(payload.readableItems.first?.sourceApp, "Files")
        XCTAssertNotNil(payload.readableItems.first?.deferredProvider)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payload.readableItems.first?.sourceURL.path ?? ""))
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
}

@MainActor
extension ShareImportModelTests {
    func testStartSaveCoalescesRepeatedRequestsIntoOneCoreImport() async throws {
        let source = try makeSharedFile(name: "Single.pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let gate = ShareImportOperationGate()
        let bridge = FakeShareImportCoreBridge(
            prediction: .fixture(category: "receipts"),
            importGate: gate
        )
        let model = makeModel(itemURLs: [source], bridge: bridge)

        await model.prepare()
        let firstTask = try XCTUnwrap(model.startSave())
        let repeatedTask = try XCTUnwrap(model.startSave())
        await gate.waitUntilStarted()

        let inFlightImports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(inFlightImports.count, 1)
        XCTAssertEqual(model.phase, .saving)
        XCTAssertFalse(model.canSave)

        await gate.finish()
        await firstTask.value
        await repeatedTask.value

        let completedImports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(completedImports.count, 1)
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(model.result, .imported(.fixture(name: "Single.pdf", category: "receipts")))
    }

    func testCancelDelayedSaveSuppressesSavedResultAndCleansImmediateStaging() async throws {
        let root = try makeTemporaryDirectory()
        let source = try makeSharedFile(name: "Cancelled.pdf")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let gate = ShareImportOperationGate()
        let bridge = FakeShareImportCoreBridge(importGate: gate)
        let queue = SharedContainerImportQueue(rootURL: root)
        let accessProbe = ShareImportAccessProbe()
        let repositoryAccess = FakeExtensionRepositoryAccess(accessProbe: accessProbe)
        let model = makeModel(
            itemURLs: [source],
            bridge: bridge,
            repositoryAccess: repositoryAccess,
            queue: queue
        )
        let lifecycle = ShareImportExtensionLifecycle()
        lifecycle.attach(model: model)

        await model.prepare()
        let saveTask = try XCTUnwrap(model.startSave())
        await gate.waitUntilStarted()
        let payloadRoot = root.appendingPathComponent("payloads", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

        lifecycle.cancel()
        let cancellationTask = Task { @MainActor in
            await lifecycle.cancelAndWait()
        }
        await gate.finish()
        await cancellationTask.value
        await saveTask.value

        let imports = await bridge.importRequestsSnapshot()
        XCTAssertEqual(imports.count, 1)
        XCTAssertTrue(imports[0].sourceURL.path.hasPrefix(payloadRoot.path + "/immediate-"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path), [])
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.result)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(accessProbe.counts.starts, 1)
        XCTAssertEqual(accessProbe.counts.stops, 1)
    }

    func testCancelAfterTicketCommitKeepsReferencedPayloadForMainApp() async throws {
        let root = try makeTemporaryDirectory()
        let first = try makeSharedFile(name: "First.pdf")
        let second = try makeSharedFile(name: "Second.pdf")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let gate = ShareImportOperationGate()
        let queue = GatedSharedContainerImportQueue(rootURL: root, ticketReturnGate: gate)
        let model = makeModel(itemURLs: [first, second], queue: queue)
        let lifecycle = ShareImportExtensionLifecycle()
        lifecycle.attach(model: model)

        await model.prepare()
        let saveTask = try XCTUnwrap(model.startSave())
        await gate.waitUntilStarted()

        let committedTickets = try await queue.pendingTickets(forRepoPath: "/tmp/Repo")
        XCTAssertEqual(committedTickets.count, 1)
        XCTAssertEqual(committedTickets[0].items.count, 2)

        lifecycle.cancel()
        let cancellationTask = Task { @MainActor in
            await lifecycle.cancelAndWait()
        }
        await gate.finish()
        await cancellationTask.value
        await saveTask.value

        let retainedTickets = try await queue.pendingTickets(forRepoPath: "/tmp/Repo")
        XCTAssertEqual(retainedTickets, committedTickets)
        for item in retainedTickets[0].items {
            let stagedURL = root.appendingPathComponent(item.stagedRelativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        }
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testSharedContainerQueueRemovesUnreferencedPayloadAfterStagingFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingSource = root.appendingPathComponent("missing.pdf")
        let item = ShareImportItem(
            sourceURL: missingSource,
            sourceApp: "Files",
            isReadable: true
        )
        let queue = SharedContainerImportQueue(rootURL: root)

        do {
            _ = try await queue.saveTicket(request: ShareImportQueueRequest(
                repoPath: "/tmp/Repo",
                category: "inbox",
                items: [item],
                needsConflictReview: false
            ))
            XCTFail("Expected ticket staging to fail for a missing source")
        } catch {
            XCTAssertNotNil(error as? ShareImportError)
        }
        try assertQueueDirectoriesContainNoPayloadOrTicket(at: root)

        do {
            _ = try await queue.stageItemForImmediateImport(item)
            XCTFail("Expected immediate staging to fail for a missing source")
        } catch {
            XCTAssertNotNil(error as? ShareImportError)
        }
        try assertQueueDirectoriesContainNoPayloadOrTicket(at: root)
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

    func testQueueConsumerKeepsNeedsReviewTicketForMainAppConfirmation() async {
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

    func testQueueConsumerKeepsMultiItemTicketForMainAppReview() async {
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

    private func waitForSave(_ model: ShareImportModel) async throws {
        let task = try XCTUnwrap(model.startSave())
        await task.value
    }

    private func assertQueueDirectoriesContainNoPayloadOrTicket(
        at root: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for directoryName in ["payloads", "tickets"] {
            let directory = root.appendingPathComponent(directoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: directory.path),
                [],
                file: file,
                line: line
            )
        }
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
