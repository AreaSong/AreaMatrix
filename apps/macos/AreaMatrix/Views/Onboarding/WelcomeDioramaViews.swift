import SwiftUI

// MARK: - Stage 1 Classify Diorama

struct StageClassifyView: View {
    @State private var phase = 0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 32) {
            classifyDiorama
            DioramaStageText(
                title: "智能引擎，自动归档",
                description: "把文件拖入视窗，底层的智能规则与 AI 将自动识别内容、建议命名，并为其在庞大复杂的目录树中寻找到最佳的物理归属。"
            )
        }
        .onAppear { startCycle() }
        .onDisappear { timerTask?.cancel() }
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
            mockAppWindow.offset(x: 70)
            floatingFileView
                .offset(x: phase >= 1 ? 80 : -150, y: phase >= 1 ? -20 : 0)
                .scaleEffect(phase >= 1 && phase <= 2 ? 0.6 : 1.0)
                .opacity(phase == 0 || phase == 1 ? 1 : 0)
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
                            .foregroundColor(WelcomePalette.teal)
                        Text("Invoice.pdf")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.black)
                    }
                )

            Text("🏷️ Finance")
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(WelcomePalette.teal)
                .foregroundColor(.white)
                .cornerRadius(4)
                .shadow(color: WelcomePalette.teal.opacity(0.4), radius: 6)
                .offset(x: 24, y: -12)
                .scaleEffect(phase == 2 ? 1 : 0.5)
                .opacity(phase == 2 ? 1 : 0)
        }
    }

    private var mockAppWindow: some View {
        MockMiniWindow(title: "AreaMatrix", width: 340, height: 180) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundColor(phase == 1 ? WelcomePalette.teal : Color.gray.opacity(0.3))
                        .background(
                            phase == 1 ? WelcomePalette.teal.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Text("Drop files here").font(.system(size: 10)).foregroundStyle(.secondary)
                    if phase == 2 {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, WelcomePalette.tealBright.opacity(0.9), .clear],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.move(edge: .leading))
                    }
                }
                .frame(height: 64).clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Label("2026", systemImage: "folder.fill").font(.system(size: 10))
                    Label("Invoices", systemImage: "folder.fill").font(.system(size: 10)).padding(.leading, 12)
                    Text("📄 Invoice.pdf")
                        .font(.system(size: 9))
                        .foregroundColor(WelcomePalette.tealBright)
                        .padding(.leading, 8).frame(height: 16)
                        .background(WelcomePalette.tealBright.opacity(0.15)).cornerRadius(2)
                        .overlay(Rectangle().frame(width: 2).foregroundColor(WelcomePalette.teal), alignment: .leading)
                        .padding(.leading, 24)
                        .opacity(phase == 3 ? 1 : 0)
                        .offset(x: phase == 3 ? 0 : -10)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.05)).cornerRadius(6)
            }
            .padding(16)
        }
    }
}

// MARK: - Stage 2 Security Diorama

struct StageSecurityView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            securityDiorama
            DioramaStageText(
                title: "零侵入，绝对的安全防线",
                description: "我们仅仅在底层建立一层可视化的超级索引。程序承诺永远不会在后台私自改动、移动或覆盖您宝贵的源文件与已有目录结构。"
            )
        }
        .onAppear { isAnimating = true }
    }

    private var securityDiorama: some View {
        ZStack {
            VStack(spacing: 40) { indexLayer; osLayer }
            shieldBarrier
            dataStreams
        }
        .frame(width: 480, height: 220)
    }

    private var indexLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(WelcomePalette.teal.opacity(0.05))
                .frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WelcomePalette.teal.opacity(0.3)))
            Text("AREAMATRIX INDEX")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(WelcomePalette.teal).offset(y: -40)
            HStack(spacing: 60) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(WelcomePalette.tealBright).frame(width: 14, height: 14)
                        .shadow(color: WelcomePalette.teal, radius: 10)
                }
            }
            .background(Rectangle().fill(WelcomePalette.tealBright.opacity(0.3)).frame(width: 200, height: 2))
        }
    }

    private var osLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.05)).frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
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
                    colors: [.clear, WelcomePalette.gold, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 440, height: 2)
                .shadow(color: WelcomePalette.gold.opacity(isAnimating ? 0.5 : 0.2), radius: isAnimating ? 20 : 10)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                .overlay(Circle().stroke(WelcomePalette.gold, lineWidth: 1))
                .overlay(Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(WelcomePalette.gold))
        }
    }

    private var dataStreams: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, WelcomePalette.tealBright],
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
}
