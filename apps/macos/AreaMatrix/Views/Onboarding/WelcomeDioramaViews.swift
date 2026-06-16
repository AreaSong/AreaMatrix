import SwiftUI

// MARK: - Stage 1 Classify Diorama

struct StageClassifyView: View {
    @State private var phase = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var scanProgress: CGFloat = 0
    @State private var highlightFlash = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.welcomeStageParallax) private var parallax
    @Environment(\.welcomeStagePhase) private var stagePhase

    var body: some View {
        VStack(spacing: 32) {
            classifyDiorama
                .welcomeStageVisualMotion()
            DioramaStageText(
                title: "智能引擎，自动归档",
                description: "把文件拖入视窗，底层的智能规则与 AI 将自动识别内容、建议命名，并为其在庞大复杂的目录树中寻找到最佳的物理归属。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.emeraldDeep
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
        .onChange(of: stagePhase, initial: true) { _, newPhase in
            if newPhase.isVisible {
                phase = 0
                startCycle()
            } else {
                timerTask?.cancel()
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == 2 {
                scanProgress = 0
                withAnimation(.linear(duration: 1.0)) { scanProgress = 1 }
            }
            if newPhase == 3 {
                withAnimation(.easeOut(duration: 0.15)) { highlightFlash = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    withAnimation(.easeOut(duration: 0.5)) { highlightFlash = false }
                }
            }
        }
    }

    private func startCycle() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1250))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { phase = (phase + 1) % 4 }
            }
        }
    }

    /// Phase 0: 文件静止  Phase 1: 飞向 drop zone  Phase 2: 扫描+标签  Phase 3: 文件落位
    private var classifyDiorama: some View {
        ZStack {
            mockAppWindow
                .offset(x: 70 + parallax.horizontal * -15, y: parallax.vertical * -10)
            floatingFileView
                .offset(x: phase >= 1 ? 80 : -150, y: phase >= 1 ? -20 : 0)
                .scaleEffect(phase >= 1 && phase <= 2 ? 0.6 : 1.0)
                .rotation3DEffect(.degrees(phase == 1 ? 25 : 0), axis: (x: 0.5, y: 1.0, z: -0.2), perspective: 0.8)
                .opacity(phase == 0 || phase == 1 ? 1 : 0)

            // 文件飞行拖尾轨迹
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(
                    colors: [AreaMatrixTheme.Colors.tealBright.opacity(0.5), .clear],
                    startPoint: .trailing, endPoint: .leading
                ))
                .frame(width: phase == 1 ? 80 : 0, height: 3)
                .offset(x: phase == 1 ? 30 : -150, y: phase == 1 ? -20 : 0)
                .animation(.easeInOut(duration: 0.6), value: phase)
        }
        .frame(width: 480, height: 220)
    }

    private var floatingFileView: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 60, height: 76)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 20))
                            .foregroundColor(AreaMatrixTheme.Colors.teal)
                        Text("Invoice.pdf")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.black)
                    }
                )

            Text("🏷️ Finance")
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AreaMatrixTheme.Colors.teal)
                .foregroundColor(.white)
                .cornerRadius(4)
                .shadow(color: AreaMatrixTheme.Colors.teal.opacity(0.4), radius: 6)
                .offset(x: 24, y: -12)
                .scaleEffect(phase == 2 ? 1 : 0.5)
                .opacity(phase == 2 ? 1 : 0)
        }
    }

    private var mockAppWindow: some View {
        AreaMatrixMiniWindow(title: "AreaMatrix", width: 340, height: 180) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundColor(phase == 1 ? AreaMatrixTheme.Colors.teal : Color.gray.opacity(0.3))
                        .background(
                            phase == 1 ? AreaMatrixTheme.Colors.teal.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Text("Drop files here").font(.system(size: 10)).foregroundStyle(.secondary)
                    if phase == 2 {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, AreaMatrixTheme.Colors.tealBright.opacity(0.9), .clear],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: scanProgress * 280)
                            .transition(.opacity)
                    }
                }
                .frame(height: 64).clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Label("2026", systemImage: "folder.fill").font(.system(size: 10))
                    Label("Invoices", systemImage: "folder.fill").font(.system(size: 10)).padding(.leading, 12)
                    Text("📄 Invoice.pdf")
                        .font(.system(size: 9))
                        .foregroundColor(colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme
                            .Colors.tealDeep)
                        .padding(.leading, 8).frame(height: 16)
                        .background((colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors
                                .tealDeep).opacity(highlightFlash ? 0.45 : 0.15)).cornerRadius(2)
                        .overlay(
                            Rectangle().frame(width: 2).foregroundColor(AreaMatrixTheme.Colors.teal),
                            alignment: .leading
                        )
                        .padding(.leading, 24)
                        .opacity(phase == 3 ? 1 : 0)
                        .offset(x: phase == 3 ? 0 : -10)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06)).cornerRadius(6)
            }
            .padding(16)
        }
    }
}

// MARK: - Stage 2 Security Diorama

struct StageSecurityView: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.welcomeStageParallax) private var parallax
    @Environment(\.welcomeStagePhase) private var stagePhase

    var body: some View {
        VStack(spacing: 32) {
            securityDiorama
                .welcomeStageVisualMotion()
            DioramaStageText(
                title: "零侵入，绝对的安全防线",
                description: "我们仅仅在底层建立一层可视化的超级索引。程序承诺永远不会在后台私自改动、移动或覆盖您宝贵的源文件与已有目录结构。",
                gradient: LinearGradient(
                    colors: [
                        colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep,
                        colorScheme == .dark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        }
        .onChange(of: stagePhase, initial: true) { _, newPhase in
            if newPhase.isVisible {
                isAnimating = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }

    private var securityDiorama: some View {
        ZStack {
            VStack(spacing: 40) { indexLayer; osLayer }
            shieldBarrier
            dataStreams
            shieldSparks
            shieldRipples
        }
        .frame(width: 480, height: 220)
    }

    private var indexLayer: some View {
        let accent = colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.tealDeep
        let accentBright = colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(colorScheme == .dark ? 0.05 : 0.1))
                .frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(colorScheme == .dark ? 0.3 : 0.4)))
            Text("AREAMATRIX INDEX")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(accent).offset(y: -40)
            HStack(spacing: 60) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(accentBright).frame(width: 14, height: 14)
                        .shadow(color: accent, radius: 10)
                }
            }
            .background(Rectangle().fill(accentBright.opacity(colorScheme == .dark ? 0.3 : 0.5)).frame(
                width: 200,
                height: 2
            ))
        }
    }

    private var osLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06)).frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            Text("MACOS FILE SYSTEM")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).offset(y: 40)
            HStack(spacing: 42) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Image(systemName: "folder.fill").font(.system(size: 26)).foregroundColor(.blue)
                }
            }
        }
    }

    private var shieldBarrier: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, AreaMatrixTheme.Colors.gold, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 440, height: 2)
                .shadow(
                    color: AreaMatrixTheme.Colors.gold.opacity(isAnimating ? 0.5 : 0.2),
                    radius: isAnimating ? 20 : 10
                )
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                .overlay(Circle().stroke(AreaMatrixTheme.Colors.gold, lineWidth: 1))
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AreaMatrixTheme.Colors.gold)
                        .symbolEffect(.pulse, value: isAnimating)
                )
                .scaleEffect(isAnimating ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.3), value: isAnimating)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(colorScheme == .dark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.gold)
                .shadow(color: AreaMatrixTheme.Colors.gold.opacity(0.4), radius: 20)
        }
        .offset(x: parallax.horizontal * 25, y: parallax.vertical * 25)
    }

    private var dataStreams: some View {
        let streamColor = colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep
        return ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, streamColor],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(width: 2, height: 40)
                    .offset(x: CGFloat([-78, 0, 78][index]), y: isAnimating ? -35 : 35)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        .easeInOut(duration: 3)
                            .repeatForever(autoreverses: false)
                            .delay(Double([0, 1.5, 0.7][index])),
                        value: isAnimating
                    )
            }
        }
    }

    private var shieldSparks: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(AreaMatrixTheme.Colors.gold)
                    .frame(width: 6, height: 6)
                    .shadow(color: AreaMatrixTheme.Colors.gold, radius: 10)
                    .offset(x: CGFloat([-78, 0, 78][index]))
                    .scaleEffect(isAnimating ? 2.5 : 0.5)
                    .opacity(isAnimating ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 0.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double([0, 1.5, 0.7][index])),
                        value: isAnimating
                    )
            }
        }
    }

    /// 盾牌碰撞扩散波纹
    private var shieldRipples: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .stroke(AreaMatrixTheme.Colors.gold.opacity(0.4), lineWidth: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: CGFloat([-78, 0, 78][index]))
                    .scaleEffect(isAnimating ? 3.0 : 0.5)
                    .opacity(isAnimating ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double([0, 1.5, 0.7][index])),
                        value: isAnimating
                    )
            }
        }
    }
}
