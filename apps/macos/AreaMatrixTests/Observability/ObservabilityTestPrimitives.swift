import Foundation

final class TestObservabilityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMilliseconds: Int64

    init(milliseconds: Int64) {
        storedMilliseconds = milliseconds
    }

    var milliseconds: Int64 {
        get { withLock { storedMilliseconds } }
        set { withLock { storedMilliseconds = newValue } }
    }

    var date: Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

final class TestObservabilityIdentifierSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String]

    init(_ identifiers: [String]) {
        self.identifiers = identifiers
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.removeFirst()
    }
}
