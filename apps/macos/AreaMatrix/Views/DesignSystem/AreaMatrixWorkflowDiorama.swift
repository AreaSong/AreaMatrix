import Foundation
import SwiftUI

struct AreaMatrixWorkflowDiorama: View {
    @State private var isAnimating = false
    @State private var pulseIn = false
    @State private var pulseOut = false
    @State private var dashPhase: CGFloat = 0
    @State private var eventRows: [AreaMatrixWorkflowEventRow] = []
    @State private var eventTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneParallax) private var parallax
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility

    private let eventActions = [
        "CREATE /docs/draft.md",
        "RENAME /docs/final.md",
        "DELETE /temp/cache.tmp",
        "SYNC LocalDB_Update"
    ]

    var body: some View {
        ZStack {
            eventsColumn.offset(x: -180)
            circuitPaths
            dataPulses
            engineCore
            databaseTarget.offset(x: 180)
        }
        .frame(width: 600, height: 220)
        .offset(x: parallax.horizontal * -20, y: parallax.vertical * -20)
        .onChange(of: sceneVisibility, initial: true) { _, newPhase in
            if newPhase.isVisible {
                restartAnimations()
            } else {
                stopAnimations()
            }
        }
    }

    private func restartAnimations() {
        isAnimating = false
        pulseIn = false
        pulseOut = false
        dashPhase = 0
        eventRows = []
        startEventStream()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isAnimating = true
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { pulseIn = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.4)) {
                pulseOut = true
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { dashPhase = 8 }
        }
    }

    private func stopAnimations() {
        eventTask?.cancel()
        isAnimating = false
        pulseIn = false
        pulseOut = false
    }

    private func startEventStream() {
        eventTask?.cancel()
        eventRows = eventActions.prefix(2).map {
            AreaMatrixWorkflowEventRow(time: currentEventTime(), action: $0)
        }

        eventTask = Task { @MainActor in
            var nextIndex = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                appendEvent(action: eventActions[nextIndex % eventActions.count])
                nextIndex += 1
            }
        }
    }

    private func appendEvent(action: String) {
        let nextRow = AreaMatrixWorkflowEventRow(time: currentEventTime(), action: action)
        withAnimation(.easeOut(duration: 0.32)) {
            eventRows.append(nextRow)
            if eventRows.count > 3 {
                eventRows.removeFirst()
            }
        }
    }

    private var eventsColumn: some View {
        VStack(spacing: 10) {
            ForEach(eventRows) { event in
                eventRow(time: event.time, action: event.action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func eventRow(time: String, action: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(colorForAction(action))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .foregroundColor(colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors
                        .tealDeep)
                    .font(.system(size: 9, design: .monospaced))
                Text(action)
                    .fontWeight(.semibold)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(colorForAction(action))
            }
            .padding(8)
        }
        .background(Color.primary.opacity(0.06))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.08)))
        .frame(width: 150)
    }

    private func colorForAction(_ action: String) -> Color {
        let isDark = colorScheme == .dark
        if action
            .hasPrefix("CREATE") { return isDark ? AreaMatrixTheme.Colors.emerald : AreaMatrixTheme.Colors.emeraldDeep }
        if action.hasPrefix("RENAME") { return isDark ? AreaMatrixTheme.Colors.gold : AreaMatrixTheme.Colors.goldDeep }
        if action
            .hasPrefix("DELETE") { return isDark ? AreaMatrixTheme.Colors.coral : AreaMatrixTheme.Colors.coralDeep }
        if action.hasPrefix("SYNC") { return AreaMatrixTheme.Colors.purple }
        return isDark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.tealDeep
    }

    private var circuitPaths: some View {
        ZStack {
            circuitPath(from: CGPoint(x: 195, y: 85), to: CGPoint(x: 260, y: 100), color: AreaMatrixTheme.Colors.purple)
            circuitPath(
                from: CGPoint(x: 195, y: 135),
                to: CGPoint(x: 260, y: 120),
                color: AreaMatrixTheme.Colors.purple
            )
            circuitPath(
                from: CGPoint(x: 345, y: 110),
                to: CGPoint(x: 430, y: 110),
                color: AreaMatrixTheme.Colors.emeraldLight
            )
        }
        .frame(width: 600, height: 220)
    }

    private func circuitPath(from start: CGPoint, to end: CGPoint, color: Color) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4], dashPhase: dashPhase))
        .foregroundColor(color.opacity(0.3))
    }

    private var dataPulses: some View {
        ZStack {
            pulse(
                color: AreaMatrixTheme.Colors.purple,
                offsetX: pulseIn ? -35 : -100,
                offsetY: pulseIn ? 0 : -15,
                visible: !pulseIn
            )
            pulse(
                color: AreaMatrixTheme.Colors.purple,
                offsetX: pulseIn ? -35 : -100,
                offsetY: pulseIn ? 0 : 15,
                visible: !pulseIn
            )
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.75), value: pulseIn)
            pulse(
                color: AreaMatrixTheme.Colors.emeraldLight,
                offsetX: pulseOut ? 135 : 50,
                offsetY: 0,
                visible: !pulseOut
            )
        }
    }

    private func pulse(color: Color, offsetX: CGFloat, offsetY: CGFloat, visible: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color, radius: 8)
            .offset(x: offsetX, y: offsetY)
            .opacity(visible ? 1 : 0)
    }

    private var engineCore: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundColor(AreaMatrixTheme.Colors.purple.opacity(0.25))
                .frame(width: 105, height: 105)
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: isAnimating)

            AreaMatrixHexagonShape()
                .fill(AreaMatrixTheme.Colors.purple.opacity(0.1))
                .overlay(AreaMatrixHexagonShape().stroke(AreaMatrixTheme.Colors.purple.opacity(0.5), lineWidth: 2))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: isAnimating)

            Image(systemName: "cpu")
                .font(.system(size: 34))
                .foregroundColor(AreaMatrixTheme.Colors.purple)
        }
        .frame(width: 110, height: 110)
        .shadow(color: AreaMatrixTheme.Colors.purple.opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 30 : 15)
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isAnimating)
    }

    private var databaseTarget: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 24))
                .foregroundColor(databaseAccent)
            Text(L10n.string("Local DB"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(databaseAccent)
        }
        .frame(width: 100, height: 100)
        .background(databaseAccent.opacity(colorScheme == .dark ? 0.05 : 0.08))
        .cornerRadius(8)
        .overlay(databaseBorder)
        .shadow(color: databaseAccent.opacity(isAnimating ? 0.4 : 0), radius: isAnimating ? 20 : 0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.4), value: isAnimating)
    }

    private var databaseBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
            .foregroundColor(databaseAccent.opacity(isAnimating ? 1 : 0.4))
    }

    private var databaseAccent: Color {
        colorScheme == .dark ? AreaMatrixTheme.Colors.emeraldLight : AreaMatrixTheme.Colors.emeraldDeep
    }

    private func currentEventTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "[HH:mm:ss]"
        return formatter.string(from: Date())
    }
}

private struct AreaMatrixWorkflowEventRow: Identifiable {
    let id = UUID()
    let time: String
    let action: String
}
