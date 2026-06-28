import SwiftUI

struct TintedCapsuleBadge: View {
    let title: String
    let tint: Color
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3
    var backgroundOpacity: Double = 0.12

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(backgroundOpacity), in: Capsule())
            .foregroundStyle(tint)
    }
}
