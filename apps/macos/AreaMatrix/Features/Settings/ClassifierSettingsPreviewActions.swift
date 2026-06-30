import Foundation

extension ClassifierSettingsModel {
    func updatePreviewFilename(_ value: String) {
        previewState.updateFilename(value)
    }

    func previewClassification() async {
        guard isLoaded, !isSaving, !isPreviewing else {
            return
        }

        let filename = previewState.filename
        guard !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let currentGeneration = previewState.beginPreview()

        do {
            let result = try await predictor.predictCategory(repoPath: repoPath, filename: filename)
            guard previewState.isCurrentGeneration(currentGeneration) else {
                return
            }
            previewState.acceptResult(result, generation: currentGeneration)
        } catch {
            guard previewState.isCurrentGeneration(currentGeneration) else {
                return
            }
            let mappedError = await ClassifierSettingsErrorFactory.previewError(
                for: error,
                mapper: errorMapper
            )
            guard previewState.isCurrentGeneration(currentGeneration) else {
                return
            }
            previewState.acceptError(mappedError, generation: currentGeneration)
        }

        previewState.finishPreview(generation: currentGeneration)
    }
}
