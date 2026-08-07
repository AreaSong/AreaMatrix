import SwiftUI

/// Shared glass surface used by feature-owned path and summary controls.
public struct AreaMatrixGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

public extension View {
    func areaMatrixGlassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(AreaMatrixGlassCardModifier(cornerRadius: cornerRadius))
    }
}

public enum AreaMatrixPathBoxStyle: Equatable, Sendable {
    case glass
    case quaternary(backgroundOpacity: Double)

    public static let plain = AreaMatrixPathBoxStyle.quaternary(backgroundOpacity: 1)
}

/// Monospaced, selectable path presentation shared by onboarding and recovery features.
public struct AreaMatrixPathBox: View {
    public let path: String
    public var style: AreaMatrixPathBoxStyle
    public var lineLimit: Int
    public var maxWidth: CGFloat
    public var alignment: Alignment

    public init(
        path: String,
        style: AreaMatrixPathBoxStyle = .glass,
        lineLimit: Int = 2,
        maxWidth: CGFloat = .infinity,
        alignment: Alignment = .center
    ) {
        self.path = path
        self.style = style
        self.lineLimit = lineLimit
        self.maxWidth = maxWidth
        self.alignment = alignment
    }

    public var body: some View {
        switch style {
        case .glass:
            pathText
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: maxWidth, alignment: alignment)
                .areaMatrixGlassCard(cornerRadius: 10)
        case let .quaternary(backgroundOpacity):
            pathText
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: maxWidth, alignment: alignment)
                .background(
                    .quaternary.opacity(backgroundOpacity),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
    }

    private var pathText: some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(lineLimit)
    }
}
