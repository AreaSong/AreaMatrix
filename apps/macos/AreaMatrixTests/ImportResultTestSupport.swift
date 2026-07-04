@testable import AreaMatrix
import XCTest

@MainActor
func waitForImportResultRoute(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ImportResultRouteState? {
    for _ in 0 ..< 100 {
        if case let .importResult(state) = model.route { return state }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import result route, got \(model.route)", file: file, line: line)
    return nil
}
