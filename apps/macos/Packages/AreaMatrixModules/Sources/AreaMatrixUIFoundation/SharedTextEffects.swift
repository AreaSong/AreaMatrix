import SwiftUI

/// Text reveal effect used by the onboarding scene copy.
public struct AreaMatrixDecodedText: View {
    public let text: String
    public var gradient: LinearGradient?

    @Environment(\.areaMatrixInteractionFeedback) private var interactionFeedback
    @State private var displayText: String = ""
    @State private var timerTask: Task<Void, Never>?

    private let asciiCharacters = Array("!@#$%^&*()_+-=[]{}|;:',.<>?/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    public init(text: String, gradient: LinearGradient? = nil) {
        self.text = text
        self.gradient = gradient
    }

    public var body: some View {
        Group {
            if let gradient {
                Text(displayText)
                    .foregroundStyle(gradient)
            } else {
                Text(displayText)
            }
        }
        .onAppear { startDecode() }
        .onChange(of: text) { _, _ in startDecode() }
        .onDisappear { timerTask?.cancel() }
    }

    private func startDecode() {
        timerTask?.cancel()
        displayText = text

        timerTask = Task { @MainActor in
            let targetCharacters = Array(text)
            var currentCharacters = Array(repeating: Character(" "), count: targetCharacters.count)

            for index in 0 ..< targetCharacters.count {
                guard await scrambleTail(from: index, target: targetCharacters, current: &currentCharacters) else {
                    return
                }
                currentCharacters[index] = targetCharacters[index]
                displayText = String(currentCharacters)
            }

            interactionFeedback.performHaptic(.levelChange)
        }
    }

    private func scrambleTail(
        from index: Int,
        target: [Character],
        current: inout [Character]
    ) async -> Bool {
        for _ in 0 ..< 2 {
            try? await Task.sleep(for: .milliseconds(12))
            guard !Task.isCancelled else { return false }

            for tailIndex in index ..< target.count {
                current[tailIndex] = target[tailIndex].isWhitespace ? " " : asciiCharacters.randomElement() ?? "#"
            }
            displayText = String(current)
        }
        return true
    }
}
