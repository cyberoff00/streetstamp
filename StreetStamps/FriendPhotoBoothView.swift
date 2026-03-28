import SwiftUI

struct FriendPhotoBoothView: View {
    @Environment(\.dismiss) private var dismiss

    let hostName: String
    let hostLoadout: RobotLoadout
    let visitorLoadout: RobotLoadout

    @State private var flashOpacity: Double = 0
    @State private var phase: BoothPhase = .ready
    @State private var cameraShakeOffset: CGFloat = 0
    @State private var photoSlideOut: CGFloat = 0
    @State private var photoAngle: Double = 0
    @State private var showShareSheet = false
    @State private var renderedImage: UIImage?
    @State private var selectedFrame: PhotoFrameStyle = .polaroid
    @State private var savedFeedback = false

    private enum BoothPhase {
        case ready
        case shooting
        case done
    }

    enum PhotoFrameStyle: String, CaseIterable {
        case polaroid, film, stamp

        var label: String {
            switch self {
            case .polaroid: return "Polaroid"
            case .film: return "Film"
            case .stamp: return "Stamp"
            }
        }

        var icon: String {
            switch self {
            case .polaroid: return "photo.on.rectangle"
            case .film: return "film"
            case .stamp: return "seal.fill"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Warm, friendly background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.93),
                    Color(red: 0.95, green: 0.92, blue: 0.88),
                    Color(red: 0.92, green: 0.89, blue: 0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle pattern dots
            patternBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer()

                // Main content area
                ZStack {
                    if phase == .done {
                        // Photo result
                        VStack(spacing: 20) {
                            photoFrameContent
                                .rotationEffect(.degrees(photoAngle))
                                .offset(y: photoSlideOut)
                                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)

                            frameStylePicker
                        }
                        .transition(.opacity)
                    } else {
                        // Camera
                        toyCameraView
                            .offset(x: cameraShakeOffset)
                            .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)

                Spacer()

                bottomBar
                    .padding(.bottom, 24)
            }

            // Flash
            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = renderedImage {
                PhotoBoothShareSheet(image: img)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.38, blue: 0.35))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.7))
                    )
                    .clipShape(Circle())
                    .appMinTapTarget()
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.t("friend_photo_booth_title"))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))

            Spacer()

            if phase == .done, renderedImage != nil {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.38, blue: 0.35))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                        .clipShape(Circle())
                        .appMinTapTarget()
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Toy Camera

    private var toyCameraView: some View {
        VStack(spacing: 24) {
            // The two characters posing
            charactersPosing
                .padding(.bottom, 4)

            // Cute toy camera body
            Button {
                takePhoto()
            } label: {
                toyCamera
            }
            .buttonStyle(CameraButtonStyle())
            .disabled(phase == .shooting)

            Text(L10n.t("friend_photo_booth_hint"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.55, green: 0.52, blue: 0.48))
        }
    }

    private var charactersPosing: some View {
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.06))
                .frame(width: 160, height: 24)
                .blur(radius: 4)
                .offset(y: 50)

            HStack(spacing: -6) {
                RobotRendererView(size: 80, face: .front, loadout: hostLoadout)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-4))

                RobotRendererView(size: 80, face: .front, loadout: visitorLoadout)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(4))
            }

        }
    }

    private var toyCamera: some View {
        ZStack {
            // Camera body
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.72, blue: 0.63),
                            Color(red: 0.24, green: 0.62, blue: 0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 200, height: 140)
                .shadow(color: Color(red: 0.20, green: 0.55, blue: 0.48).opacity(0.35), radius: 12, x: 0, y: 6)

            // Top bump (viewfinder area)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.26, green: 0.66, blue: 0.58))
                .frame(width: 80, height: 24)
                .offset(y: -72)

            // Viewfinder window
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.18, green: 0.48, blue: 0.42))
                .frame(width: 30, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 20, height: 6)
                )
                .offset(y: -72)

            // Lens outer ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.22, blue: 0.24),
                            Color(red: 0.15, green: 0.15, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2)
                )
                .offset(y: -4)

            // Lens inner
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.25, green: 0.35, blue: 0.55),
                            Color(red: 0.12, green: 0.15, blue: 0.30),
                            Color(red: 0.08, green: 0.08, blue: 0.15)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    // Lens glare
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 12, height: 12)
                        .offset(x: -8, y: -10)
                )
                .offset(y: -4)

            // Flash bulb
            Circle()
                .fill(
                    phase == .shooting
                        ? Color.yellow
                        : Color(red: 0.95, green: 0.90, blue: 0.75)
                )
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(
                    color: phase == .shooting ? Color.yellow.opacity(0.6) : .clear,
                    radius: phase == .shooting ? 10 : 0
                )
                .offset(x: 60, y: -40)
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: phase)

            // Shutter button on top
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.35, blue: 0.30), Color(red: 0.85, green: 0.25, blue: 0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: Color(red: 0.85, green: 0.25, blue: 0.22).opacity(0.3), radius: 4, x: 0, y: 2)
                .offset(x: 50, y: -68)

            // Brand label
            Text("Worldo")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
                .offset(y: 46)

            // Photo slot at the bottom
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.20, green: 0.55, blue: 0.48))
                .frame(width: 120, height: 6)
                .offset(y: 62)
        }
        .frame(width: 200, height: 160)
    }

    // MARK: - Photo Frame Content

    @ViewBuilder
    private var photoFrameContent: some View {
        switch selectedFrame {
        case .polaroid:
            polaroidFrame
        case .film:
            filmStripFrame
        case .stamp:
            stampFrame
        }
    }

    private var polaroidFrame: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.97, green: 0.95, blue: 0.90),
                                Color(red: 0.94, green: 0.91, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                photoSceneContent
            }
            .frame(width: 250, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(spacing: 5) {
                Text(dateStampText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.75, green: 0.60, blue: 0.45))
                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.25))
                    .lineLimit(1)
            }
            .frame(height: 58)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
        )
        .frame(width: 278)
    }

    private var filmStripFrame: some View {
        ZStack {
            VStack(spacing: 0) {
                filmPerforations.padding(.vertical, 5)
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                    photoSceneContent.padding(6)
                }
                .frame(height: 250)
                filmPerforations.padding(.vertical, 5)
            }
            .background(Color(red: 0.15, green: 0.14, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)

            VStack {
                HStack {
                    Text("No. \(Int.random(in: 1...36))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.7))
                    Spacer()
                    Text(dateStampText)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.5))
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                Spacer()
                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.bottom, 26)
            }
        }
        .frame(width: 278, height: 316)
    }

    private var stampFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)

            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Worldo")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(FigmaTheme.primary)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Text(L10n.t("friend_photo_stamp_subtitle"))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                    Spacer()
                    Text(dateStampShort)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(FigmaTheme.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(FigmaTheme.secondary, lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.97, green: 0.96, blue: 0.94))
                    photoSceneContent
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            FigmaTheme.primary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                        )
                }
                .frame(height: 220)
                .padding(.horizontal, 10)

                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.25))
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 278, height: 326)
        .overlay(stampPerforationBorder)
    }

    // MARK: - Shared Scene Content

    private var photoSceneContent: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.93, blue: 0.88),
                    Color(red: 0.62, green: 0.85, blue: 0.80),
                    Color(red: 0.50, green: 0.76, blue: 0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                Ellipse()
                    .fill(Color(red: 0.38, green: 0.65, blue: 0.58).opacity(0.35))
                    .frame(width: 180, height: 36)
                    .blur(radius: 4)
                    .offset(y: 8)
            }

            confettiOverlay

            HStack(spacing: -10) {
                RobotRendererView(size: 96, face: .front, loadout: hostLoadout)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-5))
                RobotRendererView(size: 96, face: .front, loadout: visitorLoadout)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(5))
            }
            .offset(y: 14)

        }
    }

    private var confettiOverlay: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat([10, 8, 12, 9, 11][i])))
                    .foregroundColor(
                        [Color.yellow, Color.orange, Color.pink, Color.mint, Color.cyan][i].opacity(0.55)
                    )
                    .offset(
                        x: CGFloat([-85, 75, -55, 90, -25][i]),
                        y: CGFloat([-75, -55, 35, 45, -18][i])
                    )
            }
        }
    }

    // MARK: - Film Perforations

    private var filmPerforations: some View {
        HStack(spacing: 10) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                    .frame(width: 10, height: 5)
            }
        }
    }

    // MARK: - Stamp Perforation Border

    private var stampPerforationBorder: some View {
        GeometryReader { geo in
            let size = geo.size
            let dotSize: CGFloat = 5
            let spacing: CGFloat = 10

            HStack(spacing: spacing) {
                ForEach(0..<Int(size.width / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color(red: 0.92, green: 0.89, blue: 0.84)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width / 2, y: -dotSize / 2)

            HStack(spacing: spacing) {
                ForEach(0..<Int(size.width / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color(red: 0.92, green: 0.89, blue: 0.84)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width / 2, y: size.height + dotSize / 2)

            VStack(spacing: spacing) {
                ForEach(0..<Int(size.height / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color(red: 0.92, green: 0.89, blue: 0.84)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: -dotSize / 2, y: size.height / 2)

            VStack(spacing: spacing) {
                ForEach(0..<Int(size.height / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color(red: 0.92, green: 0.89, blue: 0.84)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width + dotSize / 2, y: size.height / 2)
        }
    }

    // MARK: - Frame Style Picker

    private var frameStylePicker: some View {
        HStack(spacing: 12) {
            ForEach(PhotoFrameStyle.allCases, id: \.rawValue) { style in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedFrame = style
                    }
                    renderPhoto()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: style.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(style.label)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(
                        selectedFrame == style
                            ? Color(red: 0.24, green: 0.62, blue: 0.55)
                            : Color(red: 0.55, green: 0.52, blue: 0.48)
                    )
                    .frame(width: 56, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                selectedFrame == style
                                    ? Color(red: 0.24, green: 0.62, blue: 0.55).opacity(0.12)
                                    : Color.white.opacity(0.5)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selectedFrame == style ? Color(red: 0.24, green: 0.62, blue: 0.55).opacity(0.3) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 32) {
            if phase == .done {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        phase = .ready
                        photoSlideOut = 0
                        renderedImage = nil
                    }
                } label: {
                    Label(L10n.t("friend_photo_retake"), systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.42, blue: 0.38))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.white.opacity(0.8))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    saveToPhotos()
                } label: {
                    Label(
                        savedFeedback ? L10n.t("friend_photo_saved") : L10n.t("friend_photo_save"),
                        systemImage: savedFeedback ? "checkmark" : "arrow.down.to.line"
                    )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(savedFeedback ? Color(red: 0.30, green: 0.72, blue: 0.45) : FigmaTheme.primary)
                                .shadow(color: FigmaTheme.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: savedFeedback)
                }
                .buttonStyle(.plain)
                .disabled(savedFeedback)
            } else {
                Text(L10n.t("friend_photo_booth_camera_label"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.55, green: 0.52, blue: 0.48).opacity(0.6))
            }
        }
    }

    // MARK: - Background Pattern

    private var patternBackground: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 28
            let dotSize: CGFloat = 2
            let cols = Int(geo.size.width / spacing) + 1
            let rows = Int(geo.size.height / spacing) + 1

            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * spacing
                        let y = CGFloat(row) * spacing
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                            with: .color(Color.black.opacity(0.03))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func takePhoto() {
        phase = .shooting

        // Camera shake
        withAnimation(.linear(duration: 0.04).repeatCount(5, autoreverses: true)) {
            cameraShakeOffset = 3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            cameraShakeOffset = 0
        }

        // Flash
        withAnimation(.easeIn(duration: 0.06)) {
            flashOpacity = 0.85
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.25)) {
                flashOpacity = 0
            }
        }

        // Transition to photo result
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            photoAngle = Double.random(in: -4...4)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                phase = .done
            }
            renderPhoto()
        }
    }

    @MainActor
    private func renderPhoto() {
        let exportView = photoFrameContent
            .padding(16)
            .background(Color(red: 0.97, green: 0.96, blue: 0.94))

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 320, height: nil)
        renderedImage = renderer.uiImage
    }

    private func saveToPhotos() {
        guard let img = renderedImage, !savedFeedback else { return }
        Haptics.success()
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            savedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                savedFeedback = false
            }
        }
    }

    // MARK: - Helpers

    private var dateStampText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: Date())
    }

    private var dateStampShort: String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f.string(from: Date())
    }
}

// MARK: - Camera Button Style

private struct CameraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Share Sheet

private struct PhotoBoothShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.permittedArrowDirections = []
            pop.sourceView = UIView()
            pop.sourceRect = .zero
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
