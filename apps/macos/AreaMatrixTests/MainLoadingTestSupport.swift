@testable import AreaMatrix
import Foundation
import XCTest

@MainActor
func waitForMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState? {
    for _ in 0 ..< 100 {
        if case let .mainLoading(state) = model.route, predicate(state) {
            return state
        }

        await Task.yield()
    }

    XCTFail("Timed out waiting for matching main loading state, got \(model.route)", file: file, line: line)
    return nil
}
