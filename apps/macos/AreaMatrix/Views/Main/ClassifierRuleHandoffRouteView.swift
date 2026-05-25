import SwiftUI

struct ClassifierRuleHandoffRouteView: View {
    enum Mode {
        case saveRule
        case impactPreview

        var title: String { self == .saveRule ? "Save classifier rule" : "Preview classifier impact" }
        var pageID: String { self == .saveRule ? "S2-17" : "S2-18" }
        var intro: String {
            self == .saveRule
                ? "Review the rule draft before saving it for future imports."
                : "Preview impact will be calculated by the S2-18 rule impact flow."
        }
        var note: String {
            self == .saveRule
                ? "This handoff does not change the current file or save classifier rules."
                : "No files are reclassified and no rules are saved from this handoff."
        }
    }

    let mode: Mode
    let handoff: ClassifierRuleHandoff
    let onCancel: () -> Void
    let onBack: (ClassifierRuleHandoff) -> Void
    let onPreviewImpact: (ClassifierRuleHandoff) -> Void

    var body: some View {
        MainFileActionSheetContainer(title: mode.title, pageID: mode.pageID) {
            VStack(alignment: .leading, spacing: 12) {
                Text(mode.intro).font(.callout).foregroundStyle(.secondary)
                ClassifierRuleHandoffSummary(handoff: handoff)
                Text(mode.note).font(.caption).foregroundStyle(.secondary)
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            if mode == .saveRule {
                Button("Preview impact") { onPreviewImpact(handoff) }
            } else {
                Button("Back") { onBack(handoff) }
            }
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
        }
    }
}

extension ClassifierCorrectionRuleRoute {
    var handoffMode: ClassifierRuleHandoffRouteView.Mode {
        switch self {
        case .saveRule:
            .saveRule
        case .impactPreview:
            .impactPreview
        }
    }
}

private struct ClassifierRuleHandoffSummary: View {
    let handoff: ClassifierRuleHandoff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Source", handoff.sourcePageID)
            metadataRow("File", handoff.fileName)
            metadataRow("Current category before correction", handoff.currentCategory)
            metadataRow("Target category", handoff.targetCategory)
            metadataRow("Move preference", handoff.moveFile ? "Move file" : "Metadata only")
            metadataRow("Keyword candidates", handoff.draft.keywordCandidates.joined(separator: ", "))
            metadataRow("Extension candidates", extensionText)
            metadataRow("Priority", "\(handoff.draft.priority)")
        }
    }

    private var extensionText: String {
        handoff.draft.extensionCandidates.isEmpty
            ? "None"
            : handoff.draft.extensionCandidates.joined(separator: ", ")
    }
}
