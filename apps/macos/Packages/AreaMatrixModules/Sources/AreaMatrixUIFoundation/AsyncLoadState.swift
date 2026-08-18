public enum AsyncLoadState<Value, Failure> {
    case idle
    case loading
    case loaded(Value)
    case failed(Failure)
}

public enum AsyncPhaseState<Failure> {
    case idle
    case loading
    case loaded
    case failed(Failure)
}

extension AsyncPhaseState: Equatable where Failure: Equatable {}

public extension AsyncPhaseState {
    var failure: Failure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

extension AsyncLoadState: Equatable where Value: Equatable, Failure: Equatable {}

public extension AsyncLoadState {
    var value: Value? {
        guard case let .loaded(value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
