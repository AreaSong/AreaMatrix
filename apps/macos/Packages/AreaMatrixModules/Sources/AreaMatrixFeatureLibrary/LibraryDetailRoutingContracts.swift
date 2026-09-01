/// Tabs and routing requests shared by the Library list and Detail surfaces.
///
/// Localized titles remain in the App target; this package only owns the stable
/// value contract so the feature model does not depend on presentation text.
public enum DetailPaneTab: String, CaseIterable, Identifiable, Sendable {
    case meta
    case summary
    case log
    case note

    public var id: String {
        rawValue
    }
}

public enum MainDetailTabRequest: Equatable, Sendable {
    case automatic(DetailPaneTab)
}
