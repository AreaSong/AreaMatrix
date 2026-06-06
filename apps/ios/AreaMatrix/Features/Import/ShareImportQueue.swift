import Foundation

protocol SharedContainerImportQueuing: Sendable {
    func saveTicket(request: ShareImportQueueRequest) async throws -> ShareImportQueueTicket
    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem
    func removeImmediateStagedItem(_ item: ShareImportImmediateStagedItem) async throws
}

protocol SharedContainerImportTicketConsuming: Sendable {
    func pendingTickets(forRepoPath repoPath: String) async throws -> [ShareImportQueueTicket]
    func stagedFileURL(for item: ShareImportQueuedItem) async throws -> URL
    func markTicketCompleted(_ ticket: ShareImportQueueTicket) async throws
}

struct ShareImportQueueRequest: Equatable, Sendable {
    var repoPath: String
    var category: String
    var items: [ShareImportItem]
    var needsConflictReview: Bool
}

struct ShareImportImmediateStagedItem: Equatable, Sendable {
    var fileURL: URL
}

struct ShareImportQueueTicket: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var repoPath: String
    var category: String
    var items: [ShareImportQueuedItem]
    var needsConflictReview: Bool
    var createdAt: Date
}

struct ShareImportQueuedItem: Codable, Equatable, Sendable {
    var displayName: String
    var stagedRelativePath: String
    var sourceApp: String
    var sizeBytes: Int64?
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
        try createQueueDirectories(payloadDir: payloadDir, ticketDir: ticketDir)
        var queuedItems: [ShareImportQueuedItem] = []
        for item in request.items {
            queuedItems.append(try await stageItem(item, in: payloadDir, ticketID: ticketID))
        }
        guard !queuedItems.isEmpty else {
            throw ShareImportError.unsupportedItem("No supported items to import.")
        }
        let ticket = ShareImportQueueTicket(
            id: ticketID,
            repoPath: request.repoPath,
            category: request.category,
            items: queuedItems,
            needsConflictReview: request.needsConflictReview,
            createdAt: Date()
        )
        try writeTicket(ticket, to: ticketDir.appendingPathComponent("\(ticketID).json"))
        return ticket
    }

    func stageItemForImmediateImport(_ item: ShareImportItem) async throws -> ShareImportImmediateStagedItem {
        let ticketID = "immediate-\(UUID().uuidString)"
        let payloadDir = rootURL
            .appendingPathComponent("payloads", isDirectory: true)
            .appendingPathComponent(ticketID, isDirectory: true)
        try createDirectory(at: payloadDir)
        let queuedItem = try await stageItem(item, in: payloadDir, ticketID: ticketID)
        return ShareImportImmediateStagedItem(fileURL: rootURL.appendingPathComponent(queuedItem.stagedRelativePath))
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
                let sourceURL = try await deferredProvider.itemProvider.loadDeferredFileRepresentation(
                    typeIdentifier: deferredProvider.typeIdentifier
                )
                try fileManager.copyItem(at: sourceURL, to: destination)
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
    func loadDeferredFileRepresentation(typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareImportError.invalidPath(typeIdentifier))
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }
}
