import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositoryCommandPaletteMenuCommandRelay(to content: some View) -> some View {
        content.onReceive(commandRouter.commands) { command in
            guard command == .commandPaletteRequested else { return }
            toggleCommandPalette()
        }
    }

    func openImportFromCommandPalette() {
        closeCommandPalette()
        onImport()
    }

    func openSettingsFromCommandPalette() {
        closeCommandPalette()
        onOpenSettings()
    }

    func beginSearchFromCommandPalette() {
        closeCommandPalette()
        beginCommandFindSearch()
    }

    func openBatchAddTagsFromCommandPalette() {
        let route = commandPaletteBatchAddTagsRoute()
        fileActionCoordinator.routingState.batchAddTagsRoute = route
        closeCommandPalette()
    }

    func openBatchChangeCategoryFromCommandPalette() {
        let route = commandPaletteBatchChangeCategoryRoute()
        fileActionCoordinator.routingState.batchChangeCategoryRoute = route
        closeCommandPalette()
    }

    func openBatchDeleteFromCommandPalette() {
        fileActionCoordinator.routingState.batchDeleteRoute = commandPaletteBatchDeleteRoute()
        closeCommandPalette()
    }

    func openBatchRenameFromCommandPalette() {
        fileActionCoordinator.routingState.batchRenameRoute = commandPaletteBatchRenameRoute()
        closeCommandPalette()
    }

    func focusFileFromCommandPalette(_ fileID: Int64) {
        selectionModel.fileIDs = [fileID]
        closeCommandPalette()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    func openRepositoryFromCommandPalette() {
        closeCommandPalette()
        onOpenRepository()
    }

    func openHelpFromCommandPalette() {
        closeCommandPalette()
        onOpenHelp()
    }

    func openClassifierRuleEditorFromCommandPalette() {
        commandPaletteModel.clear()
        commandPaletteModel.query = ""
        searchModel.pendingSearchDestination = .classifierRuleEditor(context: nil)
    }
}
