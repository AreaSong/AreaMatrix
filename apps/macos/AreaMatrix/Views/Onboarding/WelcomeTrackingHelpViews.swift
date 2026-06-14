import Foundation
import SwiftUI

// MARK: - Stage 3 Tracking Diorama

struct StageTrackingView: View {
    @State private var showNewName = false
    @State private var isSpinning = false
    @State private var particleFlying = false
    @State private var typedMarkdownLines: [TypedMarkdownLine] = []
    @State private var timerTask: Task<Void, Never>?
    @State private var typingTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    private var markdownTypewriterLines: [(String, Color)] {
        [
            ("## Documents", Color(red: 0.337, green: 0.612, blue: 0.839)),
            ("- Finance/Invoice.pdf", colorScheme == .dark
                ? Color(red: 0.306, green: 0.788, blue: 0.69)
                : WelcomePalette.tealDeep),
            ("- Design/brand.sketch", Color(red: 0.808, green: 0.569, blue: 0.471))
        ]
    }

    var body: some View {
        VStack(spacing: 32) {
            trackingDiorama
                .welcomeStageVisualMotion()
            DioramaStageText(
                title: "全局概览，时间线级追溯",
                description: "自动生成专属的 Markdown 资料库大纲。您的每一次挪动、修改，哪怕是在系统原生的 Finder 中操作，都会被精准记录并实时回流。"
            )
        }
        .onAppear {
            startCycle()
            startTyping()
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { isSpinning = true }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) { particleFlying = true }
        }
        .onDisappear {
            timerTask?.cancel()
            typingTask?.cancel()
        }
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

    private func startTyping() {
        typingTask?.cancel()
        typingTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) {
                    typedMarkdownLines = []
                }

                for source in markdownTypewriterLines {
                    let line = TypedMarkdownLine(text: "", color: source.1)
                    withAnimation(.easeOut(duration: 0.25)) {
                        typedMarkdownLines.append(line)
                    }

                    for character in source.0 {
                        try? await Task.sleep(for: .milliseconds(34))
                        guard !Task.isCancelled else { return }
                        if let index = typedMarkdownLines.firstIndex(where: { $0.id == line.id }) {
                            typedMarkdownLines[index].text.append(character)
                        }
                    }

                    try? await Task.sleep(for: .milliseconds(120))
                }

                try? await Task.sleep(for: .seconds(1.4))
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: 10, height: 10)
                                )
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
                                .foregroundColor(colorScheme == .dark
                                    ? Color(red: 0.306, green: 0.788, blue: 0.69)
                                    : WelcomePalette.tealDeep)
                                .padding(.horizontal, 4)
                                .background(
                                    showNewName
                                        ? (colorScheme == .dark
                                            ? Color(red: 0.306, green: 0.788, blue: 0.69)
                                            : WelcomePalette.tealDeep).opacity(0.3)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                                .opacity(showNewName ? 1 : 0)
                        }
                    }
                    ForEach(typedMarkdownLines) { line in
                        Text(line.text)
                            .foregroundColor(line.color)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
            // 回传粒子（双向同步）
            Circle()
                .fill(WelcomePalette.tealBright).frame(width: 5, height: 5)
                .shadow(color: WelcomePalette.tealBright, radius: 6)
                .offset(x: particleFlying ? -25 : 25)
                .opacity(particleFlying ? 0 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false).delay(1), value: particleFlying)
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
    @State private var dashPhase: CGFloat = 0
    @State private var fsEventRows: [WelcomeFSEventRow] = []
    @State private var fsEventTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    private let fsEventActions = [
        "CREATE /docs/draft.md",
        "RENAME /docs/final.md",
        "DELETE /temp/cache.tmp",
        "SYNC LocalDB_Update"
    ]

    var body: some View {
        VStack(spacing: 32) {
            helpDiorama
                .welcomeStageVisualMotion()
            DioramaStageText(
                title: "工作流与算法揭秘",
                description: "一分钟了解 AreaMatrix 如何通过轻量级的本地索引引擎和 FSEvents 监听，帮助您彻底终结文件整理的焦虑感。"
            )
        }
        .onAppear {
            startFSEventStream()
            isAnimating = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { pulseIn = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.4)) { pulseOut = true }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { dashPhase = 8 }
        }
        .onDisappear {
            fsEventTask?.cancel()
        }
    }

    private func startFSEventStream() {
        fsEventTask?.cancel()
        fsEventRows = fsEventActions.prefix(2).map {
            WelcomeFSEventRow(time: currentFSEventTime(), action: $0)
        }

        fsEventTask = Task { @MainActor in
            var nextIndex = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                let nextRow = WelcomeFSEventRow(
                    time: currentFSEventTime(),
                    action: fsEventActions[nextIndex % fsEventActions.count]
                )

                withAnimation(.easeOut(duration: 0.32)) {
                    fsEventRows.append(nextRow)
                    if fsEventRows.count > 3 {
                        fsEventRows.removeFirst()
                    }
                }
                nextIndex += 1
            }
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
        VStack(spacing: 10) {
            ForEach(fsEventRows) { event in
                fsEvent(time: event.time, action: event.action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func fsEvent(time: String, action: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(colorForAction(action))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .foregroundColor(colorScheme == .dark ? WelcomePalette.teal : WelcomePalette.tealDeep)
                    .font(.system(size: 9, design: .monospaced))
                Text(action).fontWeight(.semibold).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colorForAction(action))
            }
            .padding(8)
        }
        .background(Color.primary.opacity(0.06)).cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.08)))
        .frame(width: 150)
    }

    private func colorForAction(_ action: String) -> Color {
        let isDark = colorScheme == .dark
        if action.hasPrefix("CREATE") { return isDark ? WelcomePalette.emerald : WelcomePalette.emeraldDeep }
        if action.hasPrefix("RENAME") { return isDark ? WelcomePalette.gold : WelcomePalette.goldDeep }
        if action.hasPrefix("DELETE") { return isDark ? WelcomePalette.coral : WelcomePalette.coralDeep }
        if action.hasPrefix("SYNC") { return WelcomePalette.purple }
        return isDark ? WelcomePalette.teal : WelcomePalette.tealDeep
    }

    private var circuitPaths: some View {
        ZStack {
            Path { path in path.move(to: CGPoint(x: 195, y: 85)); path.addLine(to: CGPoint(x: 260, y: 100)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4], dashPhase: dashPhase))
                .foregroundColor(WelcomePalette.purple.opacity(0.3))
            Path { path in path.move(to: CGPoint(x: 195, y: 135)); path.addLine(to: CGPoint(x: 260, y: 120)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4], dashPhase: dashPhase))
                .foregroundColor(WelcomePalette.purple.opacity(0.3))
            Path { path in path.move(to: CGPoint(x: 345, y: 110)); path.addLine(to: CGPoint(x: 430, y: 110)) }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4], dashPhase: dashPhase))
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
        ZStack {
            // 外围反向虚线圆环 — 齿轮副轴
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundColor(WelcomePalette.purple.opacity(0.25))
                .frame(width: 105, height: 105)
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: isAnimating)

            WelcomeHexagon()
                .fill(WelcomePalette.purple.opacity(0.1))
                .overlay(WelcomeHexagon().stroke(WelcomePalette.purple.opacity(0.5), lineWidth: 2))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: isAnimating)

            Image(systemName: "cpu")
                .font(.system(size: 34))
                .foregroundColor(WelcomePalette.purple)
        }
        .frame(width: 110, height: 110)
        .shadow(color: WelcomePalette.purple.opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 30 : 15)
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isAnimating)
    }

    private var dbTarget: some View {
        let accent = colorScheme == .dark ? WelcomePalette.emeraldLight : WelcomePalette.emeraldDeep
        return VStack(spacing: 12) {
            Image(systemName: "externaldrive.fill").font(.system(size: 24)).foregroundColor(accent)
            Text("Local DB").font(.system(size: 9, design: .monospaced)).foregroundColor(accent)
        }
        .frame(width: 100, height: 100)
        .background(accent.opacity(colorScheme == .dark ? 0.05 : 0.08)).cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(accent.opacity(isAnimating ? 1 : 0.4))
        )
        .shadow(color: accent.opacity(isAnimating ? 0.4 : 0), radius: isAnimating ? 20 : 0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.4), value: isAnimating)
    }

    private func currentFSEventTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "[HH:mm:ss]"
        return formatter.string(from: Date())
    }
}

private struct TypedMarkdownLine: Identifiable {
    let id = UUID()
    var text: String
    let color: Color
}

private struct WelcomeFSEventRow: Identifiable {
    let id = UUID()
    let time: String
    let action: String
}
