import SwiftUI
import UIKit

private struct IntroSlide: Identifiable {
    let id = UUID()
    let titleKey: String
    let subtitleKey: String
    let primaryImageName: String
    let secondaryImageName: String
    let accent: Color
}

struct IntroSlidesView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let slides: [IntroSlide] = [
        .init(
            titleKey: "intro_slide_1_title",
            subtitleKey: "intro_slide_1_subtitle",
            primaryImageName: "onboarding_intro_01",
            secondaryImageName: "onboarding_intro_02",
            accent: Color(red: 0.36, green: 0.78, blue: 0.61)
        ),
        .init(
            titleKey: "intro_slide_2_title",
            subtitleKey: "intro_slide_2_subtitle",
            primaryImageName: "onboarding_intro_03",
            secondaryImageName: "onboarding_intro_04",
            accent: Color(red: 0.53, green: 0.78, blue: 0.67)
        ),
        .init(
            titleKey: "intro_slide_3_title",
            subtitleKey: "intro_slide_3_subtitle",
            primaryImageName: "onboarding_intro_05",
            secondaryImageName: "onboarding_intro_06",
            accent: Color(red: 0.67, green: 0.82, blue: 0.76)
        ),
        .init(
            titleKey: "intro_slide_4_title",
            subtitleKey: "intro_slide_4_subtitle",
            primaryImageName: "onboarding_intro_07",
            secondaryImageName: "onboarding_intro_08",
            accent: Color(red: 0.80, green: 0.88, blue: 0.84)
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 0.98),
                    Color(red: 0.93, green: 0.97, blue: 0.95)
                ],
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
            .padding(.bottom, 16)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Worldo")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.82))

            Spacer()

            if page < slides.count - 1 {
                Button(L10n.t("intro_skip")) {
                    onFinish()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func slidePage(_ slide: IntroSlide) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)

            VStack(spacing: 14) {
                Text(L10n.t(slide.titleKey))
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: 300)

                Text(L10n.t(slide.subtitleKey))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 38, style: .continuous)
                            .stroke(.white.opacity(0.65), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 26, x: 0, y: 14)

                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [slide.accent.opacity(0.18), .white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .fill(slide.accent.opacity(0.14))
                    .frame(width: 220, height: 220)
                    .offset(x: -84, y: -46)

                Circle()
                    .fill(slide.accent.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .offset(x: 108, y: 74)

                HStack(spacing: -34) {
                    screenshotCard(
                        name: slide.primaryImageName,
                        width: 158,
                        height: 322,
                        tilt: -4,
                        accent: slide.accent
                    )
                    .offset(y: 20)

                    screenshotCard(
                        name: slide.secondaryImageName,
                        width: 170,
                        height: 344,
                        tilt: 5,
                        accent: slide.accent
                    )
                    .zIndex(1)
                }
            }
            .frame(width: 332, height: 454)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private func screenshotCard(
        name: String,
        width: CGFloat,
        height: CGFloat,
        tilt: Double,
        accent: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white)
                .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 10)

            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - 12, height: height - 12)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                placeholderCard(name: name, accent: accent)
                    .frame(width: width - 12, height: height - 12)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(tilt))
    }

    private func placeholderCard(name: String, accent: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(0.20),
                    Color.white,
                    accent.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(accent.opacity(0.95))

                Text("待加入截图")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.72))

                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<slides.count, id: \.self) { idx in
                    Capsule(style: .continuous)
                        .fill(idx == page ? slides[page].accent : Color.black.opacity(0.12))
                        .frame(width: idx == page ? 24 : 8, height: 8)
                }
            }

            Button {
                if page >= slides.count - 1 {
                    onFinish()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        page += 1
                    }
                }
            } label: {
                Text(page >= slides.count - 1 ? L10n.t("intro_get_started") : L10n.t("intro_next"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(red: 0.36, green: 0.78, blue: 0.61))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }
}
