import Foundation

extension MainFileListModel {
    func beginClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        destination: ClassifierRuleHandoffDestination
    ) {
        guard let handoff = makeClassifierRuleHandoff(
            fileID: fileID,
            targetCategory: targetCategory,
            moveFile: moveFile
        ) else {
            return
        }
        beginClassifierRuleRoute(destination.route(with: handoff), handoff: handoff)
    }

    func beginClassifierRuleSave(_ handoff: ClassifierRuleHandoff) {
        beginClassifierRuleRoute(.saveRule(handoff), handoff: handoff)
    }

    func beginClassifierImpactPreview(_ handoff: ClassifierRuleHandoff) {
        beginClassifierRuleRoute(.impactPreview(handoff), handoff: handoff)
    }

    private func beginClassifierRuleRoute(
        _ route: ClassifierCorrectionRuleRoute,
        handoff: ClassifierRuleHandoff
    ) {
        guard pendingActionDestination?.isChangeCategory(fileID: handoff.fileID) == true,
              writeActionDisabledReason(fileID: handoff.fileID) == nil else { return }
        pendingActionDestination = .changeCategory(
            fileID: handoff.fileID,
            initialTargetCategory: handoff.targetCategory,
            mode: .classifierCorrection,
            ruleRoute: route
        )
    }

    private func makeClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool
    ) -> ClassifierRuleHandoff? {
        let file = files.first { $0.id == fileID } ??
            selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
        guard let file,
              let draft = ClassifierRuleDraftSnapshot.classifierCorrectionDraft(
                  file: file,
                  targetCategory: targetCategory
              ) else { return nil }
        return ClassifierRuleHandoff(
            sourcePageID: "S2-16",
            fileID: file.id,
            fileName: file.currentName,
            currentCategory: file.category,
            targetCategory: targetCategory,
            moveFile: moveFile,
            draft: draft
        )
    }
}
