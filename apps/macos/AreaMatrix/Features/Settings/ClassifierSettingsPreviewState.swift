import Foundation

struct ClassifierSettingsPreviewState: Equatable {
    var filename = ""
    var result: ClassifyResultSnapshot?
    var error: ClassifierSettingsPreviewError?
    var isPreviewing = false
    private(set) var generation = 0

    mutating func updateFilename(_ value: String) {
        guard filename != value else { return }
        filename = value
        clear()
    }

    mutating func beginPreview() -> Int {
        generation += 1
        isPreviewing = true
        result = nil
        error = nil
        return generation
    }

    func isCurrentGeneration(_ value: Int) -> Bool {
        generation == value
    }

    mutating func acceptResult(_ value: ClassifyResultSnapshot, generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        result = value
    }

    mutating func acceptError(_ value: ClassifierSettingsPreviewError, generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        error = value
    }

    mutating func finishPreview(generation currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        isPreviewing = false
    }

    mutating func clear() {
        generation += 1
        result = nil
        error = nil
        isPreviewing = false
    }
}
