import SwiftUI

// MARK: - Stage 3 Tracking Diorama

struct StageTrackingView: View {
    @State private var showNewName = false
    @State private var isSpinning = false
    @State private var particleFlying = false
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 32) {
            trackingDiorama
            DioramaStageText(
                title: "全局概览，时间线级追溯",
                description: "自动生成专属的 Markdown 资料库大纲。您的每一次挪动、修改，哪怕是在系统原生的 Finder 中操作，都会被精准记录并实时回流。"
            )
        }
        .onAppear {
            startCycle()
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { isSpinning = true }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) { particleFlying = true }
        }
        .onDisappear { timerTask?.cancel() }
    }

    private func startCycle() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) { showNewName.toggle() }
            }
        }
    }

    private var trackingDiorama: some View {
        HStack(spacing: 20) {
            // 左：Finder 窗口
            MockMiniWindow(title: "Finder", width: 180, height: 150) {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.05)).frame(width: 40)
                    VStack(alignment: .leading) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(
                                    colors: [WelcomePalette.tealBright, WelcomePalette.teal],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 18, height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 10, height: 10))
                            ZStack(alignment: .leading) {
                                Text("Draft_v1.md").opacity(showNewName ? 0 : 1)
                                Text("Final_v2.md").foregroundColor(.green).opacity(showNewName ? 1 : 0)
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .padding(8)
                        .background(
                            showNewName ? WelcomePalette.teal.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            // 中：同步桥
            syncBridge

            // 右：Editor 窗口
            MockMiniWindow(title: "AREAMATRIX.md", width: 220, height: 150, useDarkBackground: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("# Index Graph")
                        .foregroundColor(Color(red: 0.337, green: 0.612, blue: 0.839))
                    HStack(spacing: 4) {
                        Text("- [x]").foregroundColor(Color(red: 0.808, green: 0.569, blue: 0.471))
                        ZStack(alignment: .leading) {
                            Text("Draft_v1.md").opacity(showNewName ? 0 : 1)
                            Text("Final_v2.md")
                                .foregroundColor(Color(red: 0.306, green: 0.788, blue: 0.69))
                                .padding(.horizontal, 4)
                                .background(
                                    showNewName ? Color(red: 0.306, green: 0.788, blue: 0.69).opacity(0.3) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                                .opacity(showNewName ? 1 : 0)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .frame(height: 220)
    }

    private var syncBridge: some View {
        ZStack {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 8]))
                .foregroundColor(WelcomePalette.coral.opacity(0.4))
                .frame(height: 2)
            Circle()
                .fill(WelcomePalette.coral).frame(width: 6, height: 6)
                .shadow(color: WelcomePalette.coral, radius: 8)
                .offset(x: particleFlying ? 25 : -25)
                .opacity(particleFlying ? 0 : 1)
            Circle()
                .fill(.ultraThinMaterial).frame(width: 30, height: 30)
                .overlay(Circle().stroke(WelcomePalette.coral.opacity(0.5)))
                .overlay(
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(WelcomePalette.coral)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                )
        }
        .frame(width: 60)
    }
}

// MARK: - Stage 4 Help Diorama

struct StageHelpView: View {
    @State private var isAnimating = false
    @State private var pulseIn = false
    @State private var pulseOut = false

    var body: some View {
        VStack(spacing: 32) {
            helpDiorama
            DioramaStageText(
                title: "工作流与算法揭秘",
                description: "一分钟了解 AreaMatrix 如何通过轻量级的本地索引引擎和 FSEvents 监听，帮助您彻底终结文件整理的焦虑感。"
            )
        }
        .onAppear {
            isAnimating = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { pulseIn = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.4)) { pulseOut = true }
        }
    }

    private var helpDiorama: some View {
        ZStack {
            fsEventsColumn.offset(x: -180)
            circuitPaths
            dataPulses
            engineCore
            dbTarget.offset(x: 180)
        }
        .frame(width: 600, height: 220)
    }

    private var fsEventsColumn: some View {
        VStack(spacing: 16) {
            fsEvent(time: "[13:23:28]", action: "CREATE /docs/new.md")
            fsEvent(time: "[13:23:29]", action: "RENAME /docs/old.md")
        }
    }

    private func fsEvent(time: String, action: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time).foregroundColor(WelcomePalette.teal).font(.system(size: 9, design: .monospaced))
            Text(action).fontWeight(.semibold).font(.system(size: 10, design: .monospaced))
        }
        .padding(8)
        .background(Color.black.opacity(0.05)).cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))
        .frame(width: 150)
    }

    private var circuitPaths: some View {
        ZStack {
            Path { p in p.move(to: CGPoint(x: 195, y: 85)); p.addLine(to: CGPoint(x: 260, y: 100)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(WelcomePalette.purple.opacity(0.3))
            Path { p in p.move(to: CGPoint(x: 195, y: 135)); p.addLine(to: CGPoint(x: 260, y: 120)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(WelcomePalette.purple.opacity(0.3))
            Path { p in p.move(to: CGPoint(x: 345, y: 110)); p.addLine(to: CGPoint(x: 430, y: 110)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(WelcomePalette.emeraldLight.opacity(0.3))
        }
        .frame(width: 600, height: 220)
    }

    private var dataPulses: some View {
        ZStack {
            Circle().fill(WelcomePalette.purple).frame(width: 8, height: 8)
                .shadow(color: WelcomePalette.purple, radius: 8)
                .offset(x: pulseIn ? -35 : -100, y: pulseIn ? 0 : -15)
                .opacity(pulseIn ? 0 : 1)
            Circle().fill(WelcomePalette.purple).frame(width: 8, height: 8)
                .shadow(color: WelcomePalette.purple, radius: 8)
                .offset(x: pulseIn ? -35 : -100, y: pulseIn ? 0 : 15)
                .opacity(pulseIn ? 0 : 1)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.75), value: pulseIn)
            Circle().fill(WelcomePalette.emeraldLight).frame(width: 8, height: 8)
                .shadow(color: WelcomePalette.emeraldLight, radius: 8)
                .offset(x: pulseOut ? 135 : 50)
                .opacity(pulseOut ? 0 : 1)
        }
    }

    private var engineCore: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(WelcomePalette.purple.opacity(0.1))
            .frame(width: 90, height: 90)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(WelcomePalette.purple.opacity(0.5), lineWidth: 2))
            .overlay(
                Image(systemName: "cpu").font(.system(size: 36))
                    .foregroundColor(WelcomePalette.purple)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: isAnimating)
            )
            .shadow(color: WelcomePalette.purple.opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 30 : 15)
            .scaleEffect(isAnimating ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isAnimating)
    }

    private var dbTarget: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.fill").font(.system(size: 24)).foregroundColor(WelcomePalette.emeraldLight)
            Text("Local DB").font(.system(size: 9, design: .monospaced)).foregroundColor(WelcomePalette.emeraldLight)
        }
        .frame(width: 100, height: 100)
        .background(WelcomePalette.emeraldLight.opacity(0.05)).cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(WelcomePalette.emeraldLight.opacity(isAnimating ? 1 : 0.4))
        )
        .shadow(color: WelcomePalette.emeraldLight.opacity(isAnimating ? 0.4 : 0), radius: isAnimating ? 20 : 0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.4), value: isAnimating)
    }
}
