import SwiftUI

/// Onboarding 步骤页通用的玻璃卡片表面：ultraThinMaterial 填充 + primary 10% 细描边。
struct AreaMatrixGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func areaMatrixGlassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(AreaMatrixGlassCardModifier(cornerRadius: cornerRadius))
    }
}

enum AreaMatrixPathBoxStyle: Equatable {
    /// 玻璃卡片样式：ultraThinMaterial + 细描边，圆角 10。
    case glass
    /// 朴素底色样式：quaternary 填充，圆角 6；backgroundOpacity 控制底色透明度。
    case quaternary(backgroundOpacity: Double)

    static let plain = AreaMatrixPathBoxStyle.quaternary(backgroundOpacity: 1)
}

/// 等宽、可选中的资料库路径展示框，供 onboarding 与修复页共用。
struct AreaMatrixPathBox: View {
    let path: String
    var style = AreaMatrixPathBoxStyle.glass
    var lineLimit = 2
    var maxWidth: CGFloat = .infinity
    var alignment = Alignment.center

    var body: some View {
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
