@testable import AreaMatrix
import Foundation
import XCTest

@MainActor
func requireMainLoadingState(
    _ model: OnboardingModel,
    message: String = "Expected main-loading route",
    file: StaticString = #filePath,
    line: UInt = #line
) -> MainLoadingState? {
    guard case let .mainLoading(state) = model.route else {
        XCTFail("\(message), got \(model.route)", file: file, line: line)
        return nil
    }
    return state
}

@MainActor
func waitForMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState? {
    await waitForMainActorTestValue(
        failureMessage: { "Timed out waiting for matching main loading state, got \(model.route)" },
        file: file,
        line: line,
        value: {
            if case let .mainLoading(state) = model.route, predicate(state) {
                return state
            }
            return nil
        }
    )
}
