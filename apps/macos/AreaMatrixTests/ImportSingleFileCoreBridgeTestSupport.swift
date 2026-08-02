@testable import AreaMatrix
import Foundation

@MainActor
func makeImportSingleFileNameConflictCoreModel(
    repoURL: URL,
    existingURL: URL,
    incomingURL: URL
) async throws -> ImportSingleFilePreviewModel {
    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    _ = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: existingURL,
        overrideCategory: "docs",
        overrideFilename: "source.pdf"
    )

    let model = makeImportSingleFilePreviewModel(
        importer: bridge,
        preflight: CoreImportSingleFilePreflight(
            fileLoader: CoreBridgeBatchFileLoader(fileLister: bridge),
            sourceInspector: ImportPlatformServices.sourcePreflightInspector
        )
    )
    await model.load(request: .importSingleFileImportRequest(
        repoPath: repoURL.path,
        sourcePath: incomingURL.path
    ))
    return model
}
