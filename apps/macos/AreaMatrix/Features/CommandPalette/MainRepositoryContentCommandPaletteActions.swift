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
        fileActionRoutingState.batchAddTagsRoute = route
        closeCommandPalette()
    }

    func openBatchChangeCategoryFromCommandPalette() {
        let route = commandPaletteBatchChangeCategoryRoute()
        fileActionRoutingState.batchChangeCategoryRoute = route
        closeCommandPalette()
    }

    func openBatchDeleteFromCommandPalette() {
        fileActionRoutingState.batchDeleteRoute = commandPaletteBatchDeleteRoute()
        closeCommandPalette()
    }

    func openBatchRenameFromCommandPalette() {
        fileActionRoutingState.batchRenameRoute = commandPaletteBatchRenameRoute()
        closeCommandPalette()
    }

    func focusFileFromCommandPalette(_ fileID: Int64) {
        selectedFileIDs = [fileID]
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
        fileListModel.clearCommandPaletteState()
        fileListModel.commandPaletteQuery = ""
        fileListModel.pendingSearchDestination = .classifierRuleEditor(context: nil)
    }
}
