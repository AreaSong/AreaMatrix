import SwiftUI

struct AreaMatrixProtectionDiorama: View {
    @State private var isAnimating = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.areaMatrixSceneParallax) private var parallax
    @Environment(\.areaMatrixSceneVisibility) private var sceneVisibility

    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                indexLayer
                osLayer
            }
            shieldBarrier
            dataStreams
            shieldSparks
            shieldRipples
        }
        .frame(width: 480, height: 220)
        .onChange(of: sceneVisibility, initial: true) { _, newPhase in
            if newPhase.isVisible {
                restartAnimation()
            } else {
                isAnimating = false
            }
        }
    }

    private func restartAnimation() {
        isAnimating = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isAnimating = true
        }
    }

    private var indexLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(indexAccent.opacity(colorScheme == .dark ? 0.05 : 0.1))
                .frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(indexAccent.opacity(colorScheme == .dark ? 0.3 : 0.4)))
            Text("AREAMATRIX INDEX")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(indexAccent)
                .offset(y: -40)
            indexNodes
        }
    }

    private var indexNodes: some View {
        HStack(spacing: 60) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Circle()
                    .fill(indexAccentBright)
                    .frame(width: 14, height: 14)
                    .shadow(color: indexAccent, radius: 10)
            }
        }
        .background(
            Rectangle()
                .fill(indexAccentBright.opacity(colorScheme == .dark ? 0.3 : 0.5))
                .frame(width: 200, height: 2)
        )
    }

    private var osLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 380, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            Text("MACOS FILE SYSTEM")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(y: 40)
            HStack(spacing: 42) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Image(systemName: "folder.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.blue)
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
            lockCore
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(AreaMatrixTheme.Colors.gold)
                .shadow(color: AreaMatrixTheme.Colors.gold.opacity(0.4), radius: 20)
        }
        .offset(x: parallax.horizontal * 25, y: parallax.vertical * 25)
    }

    private var lockCore: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(AreaMatrixTheme.Colors.gold, lineWidth: 1))
            .overlay(
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AreaMatrixTheme.Colors.gold)
                    .symbolEffect(.pulse, value: isAnimating)
            )
            .scaleEffect(isAnimating ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.3), value: isAnimating)
    }

    private var dataStreams: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, streamColor], startPoint: .bottom, endPoint: .top))
                    .frame(width: 2, height: 40)
                    .offset(x: impactOffsets[index], y: isAnimating ? -35 : 35)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(streamAnimation(index: index), value: isAnimating)
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
                    .offset(x: impactOffsets[index])
                    .scaleEffect(isAnimating ? 2.5 : 0.5)
                    .opacity(isAnimating ? 0 : 0.8)
                    .animation(sparkAnimation(index: index), value: isAnimating)
            }
        }
    }

    private var shieldRipples: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .stroke(AreaMatrixTheme.Colors.gold.opacity(0.4), lineWidth: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: impactOffsets[index])
                    .scaleEffect(isAnimating ? 3.0 : 0.5)
                    .opacity(isAnimating ? 0 : 0.6)
                    .animation(rippleAnimation(index: index), value: isAnimating)
            }
        }
    }

    private func streamAnimation(index: Int) -> Animation {
        .easeInOut(duration: 3)
            .repeatForever(autoreverses: false)
            .delay(impactDelays[index])
    }

    private func sparkAnimation(index: Int) -> Animation {
        .easeOut(duration: 0.8)
            .repeatForever(autoreverses: false)
            .delay(impactDelays[index])
    }

    private func rippleAnimation(index: Int) -> Animation {
        .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false)
            .delay(impactDelays[index])
    }

    private var indexAccent: Color {
        colorScheme == .dark ? AreaMatrixTheme.Colors.teal : AreaMatrixTheme.Colors.tealDeep
    }

    private var indexAccentBright: Color {
        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep
    }

    private var streamColor: Color {
        colorScheme == .dark ? AreaMatrixTheme.Colors.tealBright : AreaMatrixTheme.Colors.tealDeep
    }

    private var impactOffsets: [CGFloat] {
        [-78, 0, 78]
    }

    private var impactDelays: [Double] {
        [0, 1.5, 0.7]
    }
}
