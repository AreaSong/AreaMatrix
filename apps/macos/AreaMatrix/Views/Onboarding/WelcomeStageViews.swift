import SwiftUI

// MARK: - Stage Default

struct StageDefaultView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            Image(colorScheme == .dark ? "AreaMatrixLogoLockupDark" : "AreaMatrixLogoLockupLight")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.4), radius: 16, y: 12)

            VStack(spacing: 8) {
                Text("将散乱的文件，化作知识枢纽。")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255), .primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("无需搬运，只需指认一个本地文件夹。AreaMatrix 会为你建立结构清晰、无感同步的私人资料库。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: 560)
        }
    }
}

// MARK: - Stage 1 Classify

struct StageClassifyView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            // Diorama
            HStack(spacing: 40) {
                // Left: Drag Source
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 60, height: 76)
                        .shadow(color: Color.black.opacity(0.3), radius: 15, y: 10)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255))
                                Text("Invoice.pdf")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        )
                        .overlay(
                            Text("🏷️ Finance")
                                .font(.system(size: 9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.4), radius: 6)
                                .offset(x: 24, y: -12)
                                .scaleEffect(isAnimating ? 1 : 0.5)
                                .opacity(isAnimating ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.5).repeatForever().delay(1.5), value: isAnimating),
                            alignment: .topTrailing
                        )
                }
                .offset(x: isAnimating ? 180 : 0, y: isAnimating ? -20 : 0)
                .scaleEffect(isAnimating ? 0.6 : 1.0)
                .opacity(isAnimating ? 0 : 1)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false), value: isAnimating)

                // Right: Mock App
                VStack(spacing: 0) {
                    // Titlebar
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Spacer()
                        Text("AreaMatrix")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 28)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.15))

                    // Body
                    VStack(alignment: .leading, spacing: 12) {
                        // Drop Zone
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                                .foregroundColor(isAnimating ? Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255) : Color.gray.opacity(0.3))
                                .background(isAnimating ? Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.15) : Color.clear)
                                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)

                            Text("Drop files here")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 64)

                        // Tree
                        VStack(alignment: .leading, spacing: 6) {
                            Label("2026", systemImage: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                            Label("Invoices", systemImage: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.primary)
                                .padding(.leading, 12)

                            Text("📄 Invoice.pdf")
                                .font(.system(size: 9))
                                .foregroundColor(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                                .padding(.leading, 8)
                                .frame(height: 16)
                                .background(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255).opacity(0.15))
                                .cornerRadius(2)
                                .overlay(Rectangle().frame(width: 2).foregroundColor(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255)), alignment: .leading)
                                .padding(.leading, 24)
                                .opacity(isAnimating ? 1 : 0)
                                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(1), value: isAnimating)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .padding(16)
                }
                .frame(width: 340, height: 180)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
            }
            .rotation3DEffect(.degrees(isAnimating ? 2 : -2), axis: (x: 1, y: 0, z: 0))
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 12) {
                Text("智能引擎，自动归档")
                    .font(.system(size: 22, weight: .semibold))
                Text("把文件拖入视窗，底层的智能规则与 AI 将自动识别内容、建议命名，并为其在庞大复杂的目录树中寻找到最佳的物理归属。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Stage 2 Security

struct StageSecurityView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // Layers
                VStack(spacing: 40) {
                    // Index Layer
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.05))
                            .frame(width: 380, height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255).opacity(0.3)))
                        Text("AREA MATRIX INDEX")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255))
                            .offset(y: -40)

                        HStack(spacing: 60) {
                            Circle().fill(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                                .frame(width: 14, height: 14)
                                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255), radius: 10)
                            Circle().fill(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                                .frame(width: 14, height: 14)
                                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255), radius: 10)
                            Circle().fill(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255))
                                .frame(width: 14, height: 14)
                                .shadow(color: Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255), radius: 10)
                        }
                    }

                    // OS Layer
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 380, height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                        Text("MACOS FILE SYSTEM")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .offset(y: 40)

                        HStack(spacing: 42) {
                            Image(systemName: "folder.fill").font(.system(size: 26)).foregroundColor(.blue)
                            Image(systemName: "folder.fill").font(.system(size: 26)).foregroundColor(.blue)
                            Image(systemName: "folder.fill").font(.system(size: 26)).foregroundColor(.blue)
                        }
                    }
                }

                // Shield Barrier
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 440, height: 2)
                    .shadow(color: Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255).opacity(isAnimating ? 0.5 : 0.2), radius: isAnimating ? 20 : 10)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255), lineWidth: 1))
                    .overlay(Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(Color(red: 241 / 255, green: 184 / 255, blue: 78 / 255)))
            }
            .frame(height: 220)

            VStack(spacing: 12) {
                Text("零侵入，绝对的安全防线")
                    .font(.system(size: 22, weight: .semibold))
                Text("我们仅仅在底层建立一层可视化的超级索引。程序承诺永远不会在后台私自改动、移动或覆盖您宝贵的源文件与已有目录结构。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Stage 3 Tracking

struct StageTrackingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            HStack(spacing: 20) {
                // Finder
                mockWindow(title: "Finder", width: 180) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black.opacity(0.05)).frame(width: 40)
                        VStack {
                            HStack {
                                Image(systemName: "doc.text.fill").foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text("Draft_v1.md").opacity(isAnimating ? 0 : 1)
                                        .overlay(Text("Final_v2.md").foregroundColor(.green).opacity(isAnimating ? 1 : 0))
                                }
                                .font(.system(size: 10))
                                Spacer()
                            }
                            .padding(8)
                            Spacer()
                        }
                    }
                }

                // Sync
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255).opacity(0.4)).frame(height: 2)
                        .overlay(
                            Circle()
                                .fill(Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255))
                                .frame(width: 6, height: 6)
                                .offset(x: isAnimating ? 40 : -40)
                                .opacity(isAnimating ? 0 : 1)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
                        )
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255).opacity(0.5)))
                        .overlay(
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255))
                                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: isAnimating)
                        )
                    Rectangle().fill(Color(red: 233 / 255, green: 109 / 255, blue: 90 / 255).opacity(0.4)).frame(height: 2)
                }
                .frame(width: 60)

                // Editor
                mockWindow(title: "AREAMATRIX.md", width: 220) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("# Index Graph").foregroundColor(Color(red: 86 / 255, green: 156 / 255, blue: 214 / 255))
                        HStack(spacing: 4) {
                            Text("- [x]").foregroundColor(Color(red: 206 / 255, green: 145 / 255, blue: 120 / 255))
                            Text("Draft_v1.md").opacity(isAnimating ? 0 : 1)
                                .overlay(Text("Final_v2.md").foregroundColor(.green).opacity(isAnimating ? 1 : 0))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .frame(height: 220)

            VStack(spacing: 12) {
                Text("全局概览，时间线级追溯")
                    .font(.system(size: 22, weight: .semibold))
                Text("自动生成专属的 Markdown 资料库大纲。您的每一次挪动、修改，哪怕是在系统原生的 Finder 中操作，都会被精准记录并实时回流。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }

    private func mockWindow<Content: View>(title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Circle().fill(Color.yellow).frame(width: 8, height: 8)
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Spacer()
                Text(title)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 28)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.black.opacity(0.15))

            content()
        }
        .frame(width: width, height: 150)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
    }
}

// MARK: - Stage 4 Help

struct StageHelpView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // Events
                VStack(spacing: 16) {
                    HStack {
                        Text("[13:23:28]").foregroundColor(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255))
                        Text("CREATE /docs/new.md").fontWeight(.semibold)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))

                    HStack {
                        Text("[13:23:29]").foregroundColor(Color(red: 21 / 255, green: 180 / 255, blue: 159 / 255))
                        Text("RENAME /docs/old.md").fontWeight(.semibold)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))
                }
                .offset(x: -180)

                // Engine Core
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255).opacity(0.1))
                    .frame(width: 90, height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255).opacity(0.5), lineWidth: 2))
                    .overlay(Image(systemName: "cpu").font(.system(size: 36)).foregroundColor(Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255)))
                    .shadow(color: Color(red: 147 / 255, green: 51 / 255, blue: 234 / 255).opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 30 : 15)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isAnimating)

                // DB
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 24)).foregroundColor(Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255))
                    Text("Local DB").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255))
                }
                .frame(width: 100, height: 100)
                .background(Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255).opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundColor(Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255).opacity(isAnimating ? 1 : 0.4))
                )
                .offset(x: 180)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }
            .frame(height: 220)

            VStack(spacing: 12) {
                Text("工作流与算法揭秘")
                    .font(.system(size: 22, weight: .semibold))
                Text("一分钟了解 AreaMatrix 如何通过轻量级的本地索引引擎和 FSEvents 监听，帮助您彻底终结文件整理的焦虑感。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Stage 5 Start

struct StageStartView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255).opacity(0.6), lineWidth: 2)
                    .frame(width: isAnimating ? 300 : 150, height: isAnimating ? 300 : 150)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(.easeOut(duration: 2.5).repeatForever(autoreverses: false), value: isAnimating)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.15))
                    .frame(width: 180, height: 124)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 55 / 255, green: 202 / 255, blue: 182 / 255), lineWidth: 3))
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .white, radius: 10)
                    )
                    .shadow(color: Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(isAnimating ? 0.6 : 0.3), radius: isAnimating ? 40 : 20)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: isAnimating)
            }
            .frame(height: 220)

            VStack(spacing: 12) {
                Text("立刻开启您的本地知识库")
                    .font(.system(size: 22, weight: .semibold))
                Text("放心，我们仅仅是为您指认的文件夹建立一层索引。您可以随时停止使用，没有任何锁定风险。点击即可瞬间接管！")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
        }
        .onAppear { isAnimating = true }
    }
}
