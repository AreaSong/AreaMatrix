import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeStage: WelcomeStage = .default
    @State private var hoverStage: WelcomeStage? = nil
    @State private var isScanning = false

    /// Derived stage to show
    private var displayStage: WelcomeStage {
        hoverStage ?? activeStage
    }

    var body: some View {
        ZStack {
            // Ambient Background
            WelcomeAmbientBackground(stage: displayStage)

            // Main Window Shell
            VStack(spacing: 0) {
                // Titlebar
                titlebar

                // Content Stage
                ZStack {
                    switch displayStage {
                    case .default: StageDefaultView().transition(stageTransition)
                    case .feat1: StageClassifyView().transition(stageTransition)
                    case .feat2: StageSecurityView().transition(stageTransition)
                    case .feat3: StageTrackingView().transition(stageTransition)
                    case .feat4: StageHelpView().transition(stageTransition)
                    case .feat5: StageStartView().transition(stageTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 60)
                .padding(.top, 10)
                .padding(.bottom, 30)

                // Features Grid
                featuresGrid
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)

                // Footer
                footer
            }
            .frame(width: 860, height: 640)
            .background(
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color(red: 13 / 255, green: 40 / 255, blue: 35 / 255) : .white,
                        colorScheme == .dark ? Color(red: 7 / 255, green: 21 / 255, blue: 19 / 255) : Color(red: 242 / 255, green: 247 / 255, blue: 245 / 255),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.8 : 0.15), radius: 60, y: 30)
            // If scanning, blur out the main content
            .blur(radius: isScanning ? 12 : 0)
            .scaleEffect(isScanning ? 0.92 : 1)
            .opacity(isScanning ? 0.05 : 1)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isScanning)

            // Scanning Overlay
            if isScanning {
                scanOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var titlebar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Circle().fill(Color.yellow).frame(width: 12, height: 12)
                Circle().fill(Color.green).frame(width: 12, height: 12)
            }
            .padding(.leading, 16)

            Spacer()
            Text("AreaMatrix")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()

            // A mock theme button to balance the title bar
            Image(systemName: colorScheme == .dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .padding(.trailing, 16)
        }
        .frame(height: 48)
    }

    private var featuresGrid: some View {
        HStack(spacing: 20) {
            featureCard(
                icon: "arrow.down.doc",
                title: "拖拽归档，智能分类",
                description: "识别、重命名并自动落位",
                accentColor: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255),
                stage: .feat1
            )
            featureCard(
                icon: "checkmark.shield",
                title: "零侵入，绝对安全",
                description: "不碰原文件，真相在文件系统",
                accentColor: Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255),
                stage: .feat2
            )
            featureCard(
                icon: "rectangle.split.2x1",
                title: "全局概览，改动追溯",
                description: "生成大纲，双向同步改动日志",
                accentColor: Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255),
                stage: .feat3
            )
        }
    }

    private func featureCard(icon: String, title: String, description: String, accentColor: Color, stage: WelcomeStage) -> some View {
        let isHovered = hoverStage == stage

        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isHovered ? .white : accentColor)
                .frame(width: 40, height: 40)
                .background(isHovered ? accentColor : Color.primary.opacity(0.05))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .shadow(color: isHovered ? accentColor.opacity(0.5) : .clear, radius: 8, y: 4)
                .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1))
        .overlay(
            Rectangle()
                .fill(accentColor)
                .frame(height: 3)
                .opacity(0.5),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0), radius: 16, y: 8)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            if hovering {
                withAnimation { hoverStage = stage }
            } else {
                if hoverStage == stage {
                    withAnimation { hoverStage = nil }
                }
            }
        }
        .onTapGesture {
            withAnimation { activeStage = stage }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onLearnMore) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle")
                    Text("了解 AreaMatrix 如何工作")
                }
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation { hoverStage = hovering ? .feat4 : nil }
            }

            Spacer()

            Button(action: {
                withAnimation { isScanning = true }
                // Simulate the scanning effect before continuing to real app logic
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onContinue()
                    // reset just in case we come back
                    isScanning = false
                }
            }) {
                HStack(spacing: 6) {
                    Text("选择本地文件夹")
                    Image(systemName: "folder.badge.plus")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255), Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(8)
                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.3), radius: 6, y: 4)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation { hoverStage = hovering ? .feat5 : nil }
            }
        }
        .padding(.horizontal, 40)
        .frame(height: 80)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.05))
        .clipShape(CustomBottomCorners(radius: 12))
    }

    private var scanOverlay: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 8]))
                    .frame(width: 160, height: 160)
                    .foregroundColor(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isScanning)

                Image(colorScheme == .dark ? "AreaMatrixLogoMarkDark" : "AreaMatrixLogoMarkLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255).opacity(0.5), radius: 10)
            }

            Text("等待系统指令...")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                .shadow(color: Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255).opacity(0.4), radius: 8)
        }
        .scaleEffect(isScanning ? 1 : 0.9)
        .opacity(isScanning ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: isScanning)
    }
}

/// Helper for bottom corners
struct CustomBottomCorners: Shape {
    var radius: CGFloat = .infinity
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addArc(center: CGPoint(x: rect.width - radius, y: rect.height - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addArc(center: CGPoint(x: radius, y: rect.height - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: 0))
        return path
    }
}
