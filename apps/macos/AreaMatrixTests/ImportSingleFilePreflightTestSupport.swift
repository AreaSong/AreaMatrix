@testable import AreaMatrix
import XCTest

@MainActor
func waitForImportSingleFilePreflightToSettle(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 100 {
        if !model.preflightStatus.isChecking {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import preflight to settle", file: file, line: line)
}
