public struct ClassifierSettingsPreviewState<Result: Equatable, Failure: Equatable>: Equatable {
    public var filename: String
    public var result: Result?
    public var error: Failure?
    public var isPreviewing: Bool
    public private(set) var generation: Int

    public init(
        filename: String = "",
        result: Result? = nil,
        error: Failure? = nil,
        isPreviewing: Bool = false,
        generation: Int = 0
    ) {
        self.filename = filename
        self.result = result
        self.error = error
        self.isPreviewing = isPreviewing
        self.generation = generation
    }

    public mutating func updateFilename(_ value: String) {
        guard filename != value else { return }
        filename = value
        clear()
    }

    public mutating func beginPreview() -> Int {
        generation += 1
        isPreviewing = true
        result = nil
        error = nil
        return generation
    }

    public func isCurrentGeneration(_ value: Int) -> Bool {
        generation == value
    }

    public mutating func acceptResult(_ value: Result, generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        result = value
    }

    public mutating func acceptError(_ value: Failure, generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        error = value
    }

    public mutating func finishPreview(generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        isPreviewing = false
    }

    public mutating func clear() {
        generation += 1
        result = nil
        error = nil
        isPreviewing = false
    }
}
