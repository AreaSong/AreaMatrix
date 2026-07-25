import SwiftUI

struct AreaMatrixClassificationDiorama: View {
    @State private var phase = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var scanProgress: CGFloat = 0
    @State private var highlightFlash = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneParallax) private var parallax
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility

    var body: some View {
        ZStack {
            miniAppWindow
                .offset(x: 70 + parallax.horizontal * -15, y: parallax.vertical * -10)
            floatingFileView
                .offset(x: phase >= 1 ? 80 : -150, y: phase >= 1 ? -20 : 0)
                .scaleEffect(phase >= 1 && phase <= 2 ? 0.6 : 1.0)
                .rotation3DEffect(
                    .degrees(phase == 1 ? 25 : 0),
                    axis: (x: 0.5, y: 1.0, z: -0.2),
                    perspective: 0.8
                )
                .opacity(phase == 0 || phase == 1 ? 1 : 0)

            fileTrail
        }
        .frame(width: 480, height: 220)
        .onChange(of: sceneVisibility, initial: true) { _, newPhase in
            if newPhase.isVisible {
                phase = 0
                startCycle()
            } else {
                timerTask?.cancel()
            }
        }
        .onChange(of: phase) { _, newPhase in
            updateScanProgress(for: newPhase)
            updateHighlightFlash(for: newPhase)
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

    private func updateScanProgress(for newPhase: Int) {
        guard newPhase == 2 else { return }
        scanProgress = 0
        withAnimation(.linear(duration: 1.0)) { scanProgress = 1 }
    }

    private func updateHighlightFlash(for newPhase: Int) {
        guard newPhase == 3 else { return }
        withAnimation(.easeOut(duration: 0.15)) { highlightFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.5)) { highlightFlash = false }
        }
    }

    private var fileTrail: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(LinearGradient(
                colors: [AreaMatrixTheme.Colors.tealBright.opacity(0.5), .clear],
                startPoint: .trailing,
                endPoint: .leading
            ))
            .frame(width: phase == 1 ? 80 : 0, height: 3)
            .offset(x: phase == 1 ? 30 : -150, y: phase == 1 ? -20 : 0)
            .animation(.easeInOut(duration: 0.6), value: phase)
    }

    private var floatingFileView: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 60, height: 76)
                .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
                .overlay(fileCardContent)

            Text(L10n.string("Finance"))
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

    private var fileCardContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 20))
                .foregroundColor(AreaMatrixTheme.Colors.teal)
            Text("Invoice.pdf")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.black)
        }
    }

    private var miniAppWindow: some View {
        AreaMatrixMiniWindow(title: L10n.string("AreaMatrix"), width: 340, height: 180) {
            VStack(alignment: .leading, spacing: 12) {
                dropZone
                folderTree
            }
            .padding(16)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                .foregroundColor(phase == 1 ? AreaMatrixTheme.Colors.teal : Color.gray.opacity(0.3))
                .background(
                    phase == 1 ? AreaMatrixTheme.Colors.teal.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            Text(L10n.string("Drop files here"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if phase == 2 {
                scanSweep
            }
        }
        .frame(height: 64)
        .clipped()
    }

    private var scanSweep: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, AreaMatrixTheme.Colors.tealBright.opacity(0.9), .clear],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: scanProgress * 280)
            .transition(.opacity)
    }

    private var folderTree: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.string("2026"), systemImage: "folder.fill")
                .font(.system(size: 10))
            Label(L10n.string("Invoices"), systemImage: "folder.fill")
                .font(.system(size: 10))
                .padding(.leading, 12)
            indexedFileRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(6)
    }

    private var indexedFileRow: some View {
        Text("Invoice.pdf")
            .font(.system(size: 9))
            .foregroundColor(resolvedTeal)
            .padding(.leading, 8)
            .frame(height: 16)
            .background(resolvedTeal.opacity(highlightFlash ? 0.45 : 0.15))
            .cornerRadius(2)
            .overlay(Rectangle().frame(width: 2).foregroundColor(AreaMatrixTheme.Colors.teal), alignment: .leading)
            .padding(.leading, 24)
            .opacity(phase == 3 ? 1 : 0)
            .offset(x: phase == 3 ? 0 : -10)
    }

    private var resolvedTeal: Color {
        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep
    }
}
