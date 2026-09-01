import Foundation

protocol ShareImportQueueConsuming: Sendable {
    func consumePendingTickets(repoPath: String) async -> ShareImportQueueTakeoverReport
}

struct ShareImportQueueTakeoverReport: Equatable, Sendable {
    var imported: [MobileLibraryFile] = []
    var needsReview: [ShareImportQueueTicket] = []
    var failed: [ShareImportQueueFailure] = []

    var isEmpty: Bool {
        imported.isEmpty && needsReview.isEmpty && failed.isEmpty
    }
}

struct ShareImportQueueFailure: Equatable, Identifiable, Sendable {
    var ticketID: String
    var displayName: String
    var message: String

    var id: String {
        "\(ticketID)-\(displayName)-\(message)"
    }
}

actor ShareImportQueueConsumer: ShareImportQueueConsuming {
    private let queue: any SharedContainerImportTicketConsuming
    private let bridge: any ShareImportCoreBridge

    init(
        queue: any SharedContainerImportTicketConsuming = SharedContainerImportQueue(),
        bridge: any ShareImportCoreBridge = LiveMobileRepositoryCoreBridge()
    ) {
        self.queue = queue
        self.bridge = bridge
    }

    func consumePendingTickets(repoPath: String) async -> ShareImportQueueTakeoverReport {
        do {
            let tickets = try await queue.pendingTickets(forRepoPath: repoPath)
            return await consume(tickets: tickets, repoPath: repoPath)
        } catch {
            return ShareImportQueueTakeoverReport(failed: [
                ShareImportQueueFailure(
                    ticketID: "queue",
                    displayName: "Share import queue",
                    message: ShareImportError.map(error).message
                )
            ])
        }
    }

    private func consume(
        tickets: [ShareImportQueueTicket],
        repoPath: String
    ) async -> ShareImportQueueTakeoverReport {
        var report = ShareImportQueueTakeoverReport()
        for ticket in tickets {
            if ticket.needsConflictReview || ticket.items.count != 1 {
                report.needsReview.append(ticket)
                continue
            }
            await consume(ticket: ticket, repoPath: repoPath, report: &report)
        }
        return report
    }

    private func consume(
        ticket: ShareImportQueueTicket,
        repoPath: String,
        report: inout ShareImportQueueTakeoverReport
    ) async {
        var imported: [MobileLibraryFile] = []
        var workingTicket = ticket
        for index in workingTicket.items.indices {
            if workingTicket.items[index].state == .imported {
                continue
            }
            do {
                workingTicket.items[index].state = .importing
                try await queue.updateTicket(workingTicket)
                let item = workingTicket.items[index]
                let request = try await coreRequest(for: item, ticket: workingTicket, repoPath: repoPath)
                imported.append(try await bridge.importSharedItem(request: request))
                workingTicket.items[index].state = .imported
                try await queue.updateTicket(workingTicket)
            } catch {
                let item = workingTicket.items[index]
                report.failed.append(failure(for: item, ticket: workingTicket, error: error))
                return
            }
        }
        do {
            workingTicket.state = .completed
            try await queue.updateTicket(workingTicket)
            try await queue.markTicketCompleted(workingTicket)
            report.imported.append(contentsOf: imported)
        } catch {
            report.failed.append(failure(for: workingTicket, error: error))
        }
    }

    private func coreRequest(
        for item: ShareImportQueuedItem,
        ticket: ShareImportQueueTicket,
        repoPath: String
    ) async throws -> ShareImportCoreRequest {
        ShareImportCoreRequest(
            repoPath: repoPath,
            sourceURL: try await queue.stagedFileURL(for: item),
            filename: ShareImportItem.safeFilename(item.displayName),
            category: ticket.category.isEmpty ? "inbox" : ticket.category
        )
    }

    private func failure(
        for item: ShareImportQueuedItem,
        ticket: ShareImportQueueTicket,
        error: Error
    ) -> ShareImportQueueFailure {
        ShareImportQueueFailure(
            ticketID: ticket.id,
            displayName: item.displayName,
            message: ShareImportError.map(error).message
        )
    }

    private func failure(
        for ticket: ShareImportQueueTicket,
        error: Error
    ) -> ShareImportQueueFailure {
        ShareImportQueueFailure(
            ticketID: ticket.id,
            displayName: "Share import queue",
            message: ShareImportError.map(error).message
        )
    }
}
