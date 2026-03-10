import SwiftUI

private struct IntroSlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
}

struct IntroSlidesView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let slides: [IntroSlide] = [
        .init(
            title: "开始旅程",
            subtitle: "点击 START 开始记录移动轨迹。",
            symbol: "play.circle.fill",
            accent: FigmaTheme.primary
        ),
        .init(
            title: "记录 Memory",
            subtitle: "在地图页点 CAPTURE，随时拍照或写下当下。",
            symbol: "camera.circle.fill",
            accent: FigmaTheme.secondary
        ),
        .init(
            title: "保存旅程",
            subtitle: "结束后可保存图片、填写名称和活动标签。",
            symbol: "square.and.arrow.down.fill",
            accent: .black
        ),
        .init(
            title: "回看与整理",
            subtitle: "去 Collection 和 Memory 快速回看你的记录。",
            symbol: "map.circle.fill",
            accent: Color(red: 0.10, green: 0.45, blue: 0.98)
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, FigmaTheme.mutedBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        slidePage(slide)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
            .padding(.bottom, 20)
        }
    }

    private var topBar: some View {
        HStack {
            Text("StreetStamps")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.black.opacity(0.82))

            Spacer()

            if page < slides.count - 1 {
                Button(L10n.t("intro_skip")) {
                    onFinish()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.6))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func slidePage(_ slide: IntroSlide) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 10)
                    .frame(width: 300, height: 300)

                Circle()
                    .fill(slide.accent.opacity(0.15))
                    .frame(width: 172, height: 172)

                Image(systemName: slide.symbol)
                    .font(.system(size: 84, weight: .semibold))
                    .foregroundColor(slide.accent)
            }

            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.black.opacity(0.9))

                Text(slide.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<slides.count, id: \.self) { idx in
                    Capsule(style: .continuous)
                        .fill(idx == page ? Color.black : Color.black.opacity(0.18))
                        .frame(width: idx == page ? 24 : 8, height: 8)
                }
            }

            Button {
                if page >= slides.count - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page += 1
                    }
                }
            } label: {
                Text(page >= slides.count - 1 ? "开始使用" : "下一张")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }
}
