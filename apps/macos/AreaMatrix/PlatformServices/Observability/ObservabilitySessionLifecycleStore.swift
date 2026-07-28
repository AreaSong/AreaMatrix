import Foundation

struct ObservabilitySessionMarker: Codable, Equatable {
    enum State: String, Codable {
        case running
        case closed
    }

    let schemaVersion: Int
    let sessionID: String
    let startedAtMilliseconds: Int64
    let closedAtMilliseconds: Int64?
    let state: State
}

enum ObservabilityPreviousSession: Equatable {
    case missing
    case clean(ObservabilitySessionMarker)
    case interrupted(ObservabilitySessionMarker)
    case corrupt
}

enum ObservabilitySessionLifecycleError: Error, Equatable {
    case invalidMarker
}

struct ObservabilitySessionLifecycleStore {
    private static let markerName = "session-marker.json"
    private static let maximumMarkerBytes = 16 * 1024

    private let files: ObservabilitySafeFileOperations?
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(rootURL: URL?) {
        files = rootURL.map(ObservabilitySafeFileOperations.init(rootURL:))
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func beginSession(sessionID: String, nowMilliseconds: Int64) throws -> ObservabilityPreviousSession {
        guard let files else { return .missing }
        let previous = readPrevious(files: files, currentSessionID: sessionID)
        let marker = ObservabilitySessionMarker(
            schemaVersion: 1,
            sessionID: sessionID,
            startedAtMilliseconds: nowMilliseconds,
            closedAtMilliseconds: nil,
            state: .running
        )
        let data = try encoder.encode(marker)
        guard try files.replaceAtomically(
            data,
            name: Self.markerName,
            kind: .sessionMarker
        ) == .durable else { throw ObservabilitySafeFileError.writeFailed }
        return previous
    }

    func closeSession(
        sessionID: String,
        startedAtMilliseconds: Int64,
        nowMilliseconds: Int64
    ) throws {
        guard let files else { return }
        if let existing = try readMarker(files: files) {
            guard existing.sessionID == sessionID else { return }
            if existing.state == .closed { return }
            guard existing.startedAtMilliseconds == startedAtMilliseconds else {
                throw ObservabilitySessionLifecycleError.invalidMarker
            }
        }
        let marker = ObservabilitySessionMarker(
            schemaVersion: 1,
            sessionID: sessionID,
            startedAtMilliseconds: startedAtMilliseconds,
            closedAtMilliseconds: nowMilliseconds,
            state: .closed
        )
        let data = try encoder.encode(marker)
        guard try files.replaceAtomically(
            data,
            name: Self.markerName,
            kind: .sessionMarker
        ) == .durable else { throw ObservabilitySafeFileError.writeFailed }
    }
}

private extension ObservabilitySessionLifecycleStore {
    func readPrevious(
        files: ObservabilitySafeFileOperations,
        currentSessionID: String
    ) -> ObservabilityPreviousSession {
        do {
            guard let marker = try readMarker(files: files) else { return .missing }
            if marker.sessionID == currentSessionID { return .clean(marker) }
            if marker.state == .running { return .interrupted(marker) }
            return .clean(marker)
        } catch {
            return .corrupt
        }
    }

    func readMarker(files: ObservabilitySafeFileOperations) throws -> ObservabilitySessionMarker? {
        let data: Data
        do {
            data = try files.read(
                Self.markerName,
                kind: .sessionMarker,
                maximumBytes: Self.maximumMarkerBytes
            )
        } catch ObservabilitySafeFileError.missing {
            return nil
        }
        guard let marker = try? decoder.decode(ObservabilitySessionMarker.self, from: data),
              marker.schemaVersion == 1,
              ObservabilityOwnedFileKind.isSafeIdentifier(marker.sessionID),
              marker.startedAtMilliseconds >= 0,
              isValidState(marker)
        else { throw ObservabilitySessionLifecycleError.invalidMarker }
        return marker
    }

    func isValidState(_ marker: ObservabilitySessionMarker) -> Bool {
        switch marker.state {
        case .running:
            return marker.closedAtMilliseconds == nil
        case .closed:
            guard let closedAt = marker.closedAtMilliseconds else { return false }
            return closedAt >= marker.startedAtMilliseconds
        }
    }
}
