@testable import AreaMatrix
import XCTest

@MainActor
func waitForImportSingleFilePreflightToSettle(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    _ = await waitForMainActorTestValue(
        failureMessage: { "Timed out waiting for import preflight to settle" },
        file: file,
        line: line,
        value: {
            model.preflightStatus.isChecking ? nil : true
        }
    )
}
