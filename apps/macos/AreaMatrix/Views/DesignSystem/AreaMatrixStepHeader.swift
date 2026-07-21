import SwiftUI

/// Onboarding 步骤页默认的头部图标：48pt light 系统符号 + tint。
struct AreaMatrixStepHeaderIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 48, weight: .light))
            .foregroundStyle(tint)
    }
}

/// Onboarding 步骤页通用的居中大标题头：图标插槽 + 32pt semibold 标题 + title3 副标题。
struct AreaMatrixStepHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            icon()
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
}

extension AreaMatrixStepHeader where Icon == AreaMatrixStepHeaderIcon {
    init(systemImage: String, tint: Color, title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            AreaMatrixStepHeaderIcon(systemImage: systemImage, tint: tint)
        }
    }
}
