import Foundation

protocol SharedContainerImportQueuing: Sendable {
    func saveTicket(request: ShareImportQueueRequest) async throws -> ShareImportQueueTicket
    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem
    func removeImmediateStagedItem(_ item: ShareImportImmediateStagedItem) async throws
}

protocol SharedContainerImportTicketConsuming: Sendable {
    func pendingTickets(forRepoPath repoPath: String) async throws -> [ShareImportQueueTicket]
    func stagedFileURL(for item: ShareImportQueuedItem) async throws -> URL
    func updateTicket(_ ticket: ShareImportQueueTicket) async throws
    func markTicketCompleted(_ ticket: ShareImportQueueTicket) async throws
}

extension SharedContainerImportTicketConsuming {
    func updateTicket(_: ShareImportQueueTicket) async throws {}
}

struct ShareImportQueueRequest: Equatable {
    var repoPath: String
    var category: String
    var items: [ShareImportItem]
    var needsConflictReview: Bool
}

struct ShareImportImmediateStagedItem: Equatable {
    var fileURL: URL
}

enum ShareImportQueueTicketState: String, Codable, Equatable {
    case committed
    case completed
}

enum ShareImportQueuedItemState: String, Codable, Equatable {
    case pending
    case importing
    case imported
}

struct ShareImportQueueTicket: Codable, Equatable, Identifiable {
    var id: String
    var repoPath: String
    var category: String
    var items: [ShareImportQueuedItem]
    var needsConflictReview: Bool
    var createdAt: Date
    var state: ShareImportQueueTicketState

    init(
        id: String,
        repoPath: String,
        category: String,
        items: [ShareImportQueuedItem],
        needsConflictReview: Bool,
        createdAt: Date,
        state: ShareImportQueueTicketState = .committed
    ) {
        self.id = id
        self.repoPath = repoPath
        self.category = category
        self.items = items
        self.needsConflictReview = needsConflictReview
        self.createdAt = createdAt
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, repoPath, category, items, needsConflictReview, createdAt, state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        repoPath = try container.decode(String.self, forKey: .repoPath)
        category = try container.decode(String.self, forKey: .category)
        items = try container.decode([ShareImportQueuedItem].self, forKey: .items)
        needsConflictReview = try container.decode(Bool.self, forKey: .needsConflictReview)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        state = try container.decodeIfPresent(ShareImportQueueTicketState.self, forKey: .state) ?? .committed
    }
}

struct ShareImportQueuedItem: Codable, Equatable {
    var id: String
    var displayName: String
    var stagedRelativePath: String
    var sourceApp: String
    var sizeBytes: Int64?
    var state: ShareImportQueuedItemState

    init(
        id: String = UUID().uuidString,
        displayName: String,
        stagedRelativePath: String,
        sourceApp: String,
        sizeBytes: Int64?,
        state: ShareImportQueuedItemState = .pending
    ) {
        self.id = id
        self.displayName = displayName
        self.stagedRelativePath = stagedRelativePath
        self.sourceApp = sourceApp
        self.sizeBytes = sizeBytes
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, stagedRelativePath, sourceApp, sizeBytes, state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "legacy-\(UUID().uuidString)"
        displayName = try container.decode(String.self, forKey: .displayName)
        stagedRelativePath = try container.decode(String.self, forKey: .stagedRelativePath)
        sourceApp = try container.decode(String.self, forKey: .sourceApp)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        state = try container.decodeIfPresent(ShareImportQueuedItemState.self, forKey: .state) ?? .pending
    }
}

actor SharedContainerImportQueue: SharedContainerImportQueuing, SharedContainerImportTicketConsuming {
    private let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL = SharedContainerImportQueue.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func saveTicket(request: ShareImportQueueRequest) async throws -> ShareImportQueueTicket {
        let ticketID = UUID().uuidString
        let payloadRoot = rootURL.appendingPathComponent("payloads", isDirectory: true)
        let payloadDir = payloadRoot.appendingPathComponent(ticketID, isDirectory: true)
        let ticketDir = rootURL.appendingPathComponent("tickets", isDirectory: true)
        let ticketURL = ticketDir.appendingPathComponent("\(ticketID).json")
        do {
            try createQueueDirectories(payloadDir: payloadDir, ticketDir: ticketDir)
            var queuedItems: [ShareImportQueuedItem] = []
            for item in request.items {
                try Task.checkCancellation()
                let queuedItem = try await stageItem(item, in: payloadDir, ticketID: ticketID)
                queuedItems.append(queuedItem)
            }
            guard !queuedItems.isEmpty else {
                throw ShareImportError.unsupportedItem("No supported items to import.")
            }
            try Task.checkCancellation()
            let ticket = ShareImportQueueTicket(
                id: ticketID,
                repoPath: request.repoPath,
                category: request.category,
                items: queuedItems,
                needsConflictReview: request.needsConflictReview,
                createdAt: Date()
            )
            try writeTicket(ticket, to: ticketURL)
            return ticket
        } catch {
            // Cancellation/failure must not leave an unreferenced payload in
            // the shared container.
            try? fileManager.removeItem(at: ticketURL)
            try? fileManager.removeItem(at: payloadDir)
            throw error
        }
    }

    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem {
        let ticketID = "immediate-\(UUID().uuidString)"
        let payloadDir = rootURL
            .appendingPathComponent("payloads", isDirectory: true)
            .appendingPathComponent(ticketID, isDirectory: true)
        do {
            try createDirectory(at: payloadDir)
            try Task.checkCancellation()
            let queuedItem = try await stageItem(item, in: payloadDir, ticketID: ticketID)
            try Task.checkCancellation()
            return ShareImportImmediateStagedItem(
                fileURL: rootURL.appendingPathComponent(queuedItem.stagedRelativePath)
            )
        } catch {
            try? fileManager.removeItem(at: payloadDir)
            throw error
        }
    }

    func removeImmediateStagedItem(_ item: ShareImportImmediateStagedItem) async throws {
        let stagedURL = item.fileURL.standardizedFileURL
        let payloadRoot = rootURL.appendingPathComponent("payloads", isDirectory: true).standardizedFileURL
        guard stagedURL.path.hasPrefix(payloadRoot.path + "/immediate-") else {
            throw ShareImportError.invalidPath(stagedURL.path)
        }
        let batchDir = stagedURL.deletingLastPathComponent()
        do {
            if fileManager.fileExists(atPath: batchDir.path) {
                try fileManager.removeItem(at: batchDir)
            }
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    func pendingTickets(forRepoPath repoPath: String) async throws -> [ShareImportQueueTicket] {
        let ticketDir = rootURL.appendingPathComponent("tickets", isDirectory: true)
        guard fileManager.fileExists(atPath: ticketDir.path) else {
            return []
        }
        do {
            let ticketURLs = try fileManager.contentsOfDirectory(
                at: ticketDir,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            return try ticketURLs
                .filter { $0.pathExtension == "json" }
                .map { try readTicket(from: $0) }
                .filter { $0.repoPath == repoPath }
                .sorted { $0.createdAt < $1.createdAt }
        } catch let error as ShareImportError {
            throw error
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    func stagedFileURL(for item: ShareImportQueuedItem) async throws -> URL {
        let stagedURL = rootURL.appendingPathComponent(item.stagedRelativePath, isDirectory: false).standardizedFileURL
        guard stagedURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw ShareImportError.invalidPath(item.stagedRelativePath)
        }
        guard fileManager.isReadableFile(atPath: stagedURL.path) else {
            throw ShareImportError.permissionDenied(stagedURL.path)
        }
        return stagedURL
    }

    func markTicketCompleted(_ ticket: ShareImportQueueTicket) async throws {
        let ticketURL = rootURL
            .appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent("\(ticket.id).json")
        let payloadURL = rootURL
            .appendingPathComponent("payloads", isDirectory: true)
            .appendingPathComponent(ticket.id, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: ticketURL.path) {
                try fileManager.removeItem(at: ticketURL)
            }
            if fileManager.fileExists(atPath: payloadURL.path) {
                try fileManager.removeItem(at: payloadURL)
            }
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    func updateTicket(_ ticket: ShareImportQueueTicket) async throws {
        let ticketURL = rootURL
            .appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent("\(ticket.id).json")
        guard fileManager.fileExists(atPath: ticketURL.path) else {
            throw ShareImportError.invalidPath(ticketURL.path)
        }
        try writeTicket(ticket, to: ticketURL)
    }

    private func createQueueDirectories(payloadDir: URL, ticketDir: URL) throws {
        try createDirectory(at: payloadDir)
        try createDirectory(at: ticketDir)
    }

    private func createDirectory(at url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    private func stageItem(
        _ item: ShareImportItem,
        in payloadDir: URL,
        ticketID: String
    ) async throws -> ShareImportQueuedItem {
        guard item.isReadable else {
            throw ShareImportError.io(item.sourceURL.path)
        }
        let destination = uniqueDestination(in: payloadDir, filename: item.safeFilename)
        try await materialize(item, to: destination)
        return ShareImportQueuedItem(
            displayName: item.displayName,
            stagedRelativePath: "payloads/\(ticketID)/\(destination.lastPathComponent)",
            sourceApp: item.sourceApp,
            sizeBytes: item.sizeBytes
        )
    }

    private func materialize(_ item: ShareImportItem, to destination: URL) async throws {
        do {
            if let deferredProvider = item.deferredProvider {
                try await deferredProvider.itemProvider.copyDeferredFileRepresentation(
                    typeIdentifier: deferredProvider.typeIdentifier,
                    to: destination
                )
                return
            }
            switch item.kind {
            case .file:
                try fileManager.copyItem(at: item.sourceURL, to: destination)
            case .url:
                try Data(item.sourceURL.absoluteString.utf8).write(to: destination, options: .atomic)
            }
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    private func uniqueDestination(in directory: URL, filename: String) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }
        let baseURL = URL(fileURLWithPath: filename)
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 2
        repeat {
            let suffix = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = directory.appendingPathComponent(suffix)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func writeTicket(_ ticket: ShareImportQueueTicket, to url: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(ticket).write(to: url, options: .atomic)
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    private func readTicket(from url: URL) throws -> ShareImportQueueTicket {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ShareImportQueueTicket.self, from: Data(contentsOf: url))
        } catch {
            throw ShareImportError.io(error.localizedDescription)
        }
    }

    static func defaultRootURL() -> URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.areamatrix.shared"
        ) {
            return groupURL.appendingPathComponent("ShareImportQueue", isDirectory: true)
        }
        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return supportURL
                .appendingPathComponent("AreaMatrix", isDirectory: true)
                .appendingPathComponent("ShareImportQueue", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixShareImportQueue", isDirectory: true)
    }
}

private extension NSItemProvider {
    func copyDeferredFileRepresentation(
        typeIdentifier: String,
        to destination: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareImportError.invalidPath(typeIdentifier))
                    return
                }
                do {
                    // NSItemProvider only guarantees this URL during the
                    // callback, so copy it before returning to async code.
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
