import Foundation

extension MainFileListModel {
    func collectCurrentListDiagnostics() async {
        guard diagnosticsState != .collecting else { return }

        diagnosticsState = .collecting
        do {
            diagnosticsState = try await .collected(diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath))
        } catch {
            diagnosticsState = await .failed(mapCoreError(error))
        }
    }

    func clearDiagnosticsState() {
        diagnosticsState = .idle
    }
}
