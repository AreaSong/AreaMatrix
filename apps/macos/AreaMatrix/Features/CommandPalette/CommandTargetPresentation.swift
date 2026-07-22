import Foundation

enum CommandTargetPresentation {
    // Stable Core target IDs are intentionally mapped explicitly for localization.
    // swiftlint:disable:next cyclomatic_complexity
    static func title(for target: CommandTarget) -> String {
        switch normalizedID(target.id) {
        case "command.import-files": L10n.string("Import files...")
        case "command.open-repository": L10n.string("Open repository...")
        case "command.search-files": L10n.string("Search files...")
        case "command.help": L10n.string("Help")
        case "command.redo-latest-action": L10n.string("Redo latest action")
        case "command.review-import-conflicts": L10n.string("Review import conflicts")
        case "command.review-tag-suggestions": L10n.string("Review tag suggestions")
        case "command.open-classifier-rules": L10n.string("Open classifier rules...")
        case "command.preview-classifier-rule-impact": L10n.string("Preview classifier rule impact...")
        case "command.apply-classifier-rule": L10n.string("Apply classifier rule...")
        case "nav.settings": L10n.string("Settings")
        case "nav.smart-lists": L10n.string("Smart Lists")
        case "nav.needs-review": L10n.string("Needs Review")
        case "selection.add-tags": selectionTitle(target.title, base: L10n.string("Add tags"))
        case "selection.change-category": selectionTitle(target.title, base: L10n.string("Change category"))
        case "selection.rename": selectionTitle(target.title, base: L10n.string("Rename"))
        case "selection.delete": selectionTitle(target.title, base: L10n.string("Delete"))
        default: target.title
        }
    }

    // Stable Core target IDs are intentionally mapped explicitly for localization.
    // swiftlint:disable:next cyclomatic_complexity
    static func subtitle(for target: CommandTarget) -> String? {
        guard let subtitle = target.subtitle else { return nil }
        switch normalizedID(target.id) {
        case "command.import-files": return L10n.string("Open the import sheet")
        case "command.open-repository": return L10n.string("Choose an AreaMatrix repository")
        case "command.search-files": return L10n.string("Open repository search")
        case "command.help": return L10n.string("Open AreaMatrix help")
        case "command.redo-latest-action":
            return target.disabledReason != nil
                ? L10n.string("Redo stack is unavailable.")
                : L10n.string("Open redo queue")
        case "command.review-import-conflicts": return L10n.string("Open import conflict review")
        case "command.review-tag-suggestions": return L10n.string("Open tag suggestions")
        case "command.open-classifier-rules": return L10n.string("Open classifier rule editor")
        case "command.preview-classifier-rule-impact":
            return target.disabledReason != nil
                ? L10n.string("Open classifier rules first.")
                : L10n.string("Open classifier rule impact preview")
        case "command.apply-classifier-rule":
            return target.disabledReason != nil
                ? L10n.string("Open classifier rules first.")
                : L10n.string("Open classifier rule impact preview before applying")
        case "nav.settings": return L10n.string("Open repository settings")
        case "nav.smart-lists": return L10n.string("Open Smart Lists")
        case "nav.needs-review": return L10n.string("Open review queue")
        case "selection.add-tags": return selectionSubtitle(subtitle, fallback: L10n.string("Open tag editor"))
        case "selection.change-category":
            return selectionSubtitle(subtitle, fallback: L10n.string("Preview category change"))
        case "selection.rename": return selectionSubtitle(subtitle, fallback: L10n.string("Preview rename"))
        case "selection.delete":
            return selectionSubtitle(subtitle, fallback: L10n.string("Open delete confirmation"))
        default: return subtitle
        }
    }

    static func disabledReason(for target: CommandTarget) -> String? {
        guard let reason = target.disabledReason else { return nil }
        return switch reason {
        case "Redo stack is unavailable.": L10n.string("Redo stack is unavailable.")
        case "Open classifier rules first.": L10n.string("Open classifier rules first.")
        case "Select files first.": L10n.string("Select files first.")
        case "Selected files are unavailable.": L10n.string("Selected files are unavailable.")
        default: reason
        }
    }

    private static func normalizedID(_ id: String) -> String {
        id.hasPrefix("recent:") ? String(id.dropFirst("recent:".count)) : id
    }

    private static func selectionTitle(_ title: String, base: String) -> String {
        guard title.contains("selected file") else { return base }
        let count = title.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.last
        if let count {
            return L10n.format("%@ %d selected files...", base, count)
        }
        if title.contains("selected files") {
            return L10n.format("%@ selected files...", base)
        }
        return L10n.format("%@ selected file...", base)
    }

    private static func selectionSubtitle(_ subtitle: String, fallback: String) -> String {
        switch subtitle {
        case "Select files first.": L10n.string("Select files first.")
        case "Selected files are unavailable.": L10n.string("Selected files are unavailable.")
        default: fallback
        }
    }
}
