import SwiftUI

/// Shared recovery shell for a page whose selected resource disappeared.
///
/// The caller supplies localized copy so this UI Foundation component does not
/// own product wording or feature-specific recovery semantics.
public struct AreaMatrixUnavailableActionContext: View {
    public let message: String
    public let cancelTitle: String
    public let onCancel: () -> Void

    public init(message: String, cancelTitle: String, onCancel: @escaping () -> Void) {
        self.message = message
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
