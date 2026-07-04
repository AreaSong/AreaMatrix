@testable import AreaMatrix

@MainActor
func aiSummaryIntegrationModel(
    fileID: Int64,
    summary: AISummaryIntegrationSummaryBridge = AISummaryIntegrationSummaryBridge(drafts: []),
    privacy: AISummaryIntegrationPrivacyBridge = AISummaryIntegrationPrivacyBridge()
) -> AISummaryEditorModel {
    AISummaryEditorModel(
        repoPath: "/tmp/repo",
        fileID: fileID,
        summaryStore: summary,
        privacyRules: privacy,
        errorMapper: RecordingCoreErrorMapper.aiSummaryIntegration(),
        summaryProviderScope: .remoteAllowed,
        privacyContext: AISummaryPrivacyContext(
            repoRelativePath: "docs/summary.pdf",
            fileName: "summary.pdf",
            category: "docs",
            fileExtension: "pdf",
            tags: ["client"]
        )
    )
}
