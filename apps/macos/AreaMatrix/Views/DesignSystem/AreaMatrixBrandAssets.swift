import SwiftUI

struct AreaMatrixCrossfadeAssetImage: View {
    let darkName: String
    let lightName: String
    let width: CGFloat?
    let height: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            assetImage(lightName)
                .opacity(colorScheme == .dark ? 0 : 1)
            assetImage(darkName)
                .opacity(colorScheme == .dark ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.6), value: colorScheme)
    }

    private func assetImage(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}

struct AreaMatrixTrafficLights: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            trafficLight(color: Color(red: 1, green: 0.373, blue: 0.337), symbol: "xmark")
            trafficLight(color: Color(red: 1, green: 0.741, blue: 0.18), symbol: "minus")
            trafficLight(color: Color(red: 0.153, green: 0.788, blue: 0.247), symbol: "plus")
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private func trafficLight(color: Color, symbol: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.black.opacity(0.52))
                    .opacity(isHovered ? 1 : 0)
            )
    }
}

struct AreaMatrixMiniWindow<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var useDarkBackground = false
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            content()
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
    }

    private var titlebar: some View {
        HStack(spacing: 8) {
            AreaMatrixTrafficLights()
                .scaleEffect(0.67)
                .frame(width: 34, height: 12)
            Spacer()
            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.trailing, 28)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.primary.opacity(0.08))
    }

    private var borderColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.1)
    }
}

struct AreaMatrixBottomCornersShape: Shape {
    var radius: CGFloat = .infinity

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addArc(
            center: CGPoint(x: rect.width - radius, y: rect.height - radius),
            radius: radius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addArc(
            center: CGPoint(x: radius, y: rect.height - radius),
            radius: radius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: 0))
        return path
    }
}

struct AreaMatrixHexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        for index in 0 ..< 6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

struct AreaMatrixFolderShape: Shape {
    let tabWidth: CGFloat
    let tabHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let tabRadius = min(cornerRadius, tabWidth / 2, tabHeight / 2)
        let bodyRadius = cornerRadius
        var path = Path()

        path.move(to: CGPoint(x: 0, y: tabRadius))
        path.addArc(center: CGPoint(x: tabRadius, y: tabRadius), radius: tabRadius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: tabWidth - tabRadius, y: 0))
        path.addArc(center: CGPoint(x: tabWidth - tabRadius, y: tabRadius), radius: tabRadius,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: tabWidth, y: tabHeight))
        path.addLine(to: CGPoint(x: rect.width - bodyRadius, y: tabHeight))
        path.addArc(center: CGPoint(x: rect.width - bodyRadius, y: tabHeight + bodyRadius), radius: bodyRadius,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - bodyRadius))
        path.addArc(center: CGPoint(x: rect.width - bodyRadius, y: rect.height - bodyRadius), radius: bodyRadius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: bodyRadius, y: rect.height))
        path.addArc(center: CGPoint(x: bodyRadius, y: rect.height - bodyRadius), radius: bodyRadius,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()

        return path
    }
}

struct AreaMatrixNoiseOverlay: View {
    @State private var noiseImage: Image?

    var body: some View {
        Group {
            if let noiseImage {
                noiseImage
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
            } else {
                Color.clear
            }
        }
        .onAppear {
            noiseImage = generateNoiseImage()
        }
    }

    private func generateNoiseImage() -> Image? {
        let width = 128
        let height = 128
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var data = [UInt8](repeating: 0, count: width * height)
        for index in 0 ..< data.count {
            data[index] = UInt8.random(in: 0 ... 255)
        }
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        guard let cgImage = context.makeImage() else { return nil }
        return Image(cgImage, scale: 1, label: Text(L10n.string("Noise")))
    }
}
