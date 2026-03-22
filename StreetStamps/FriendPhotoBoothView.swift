import SwiftUI

struct FriendPhotoBoothView: View {
    @Environment(\.dismiss) private var dismiss

    let hostName: String
    let hostLoadout: RobotLoadout
    let visitorLoadout: RobotLoadout

    @State private var flashOpacity: Double = 0
    @State private var photoTaken = false
    @State private var photoDropAngle: Double = -8
    @State private var photoDropOffset: CGFloat = -600
    @State private var showShareSheet = false
    @State private var renderedImage: UIImage?
    @State private var selectedFrame: PhotoFrameStyle = .polaroid

    enum PhotoFrameStyle: String, CaseIterable {
        case polaroid
        case film
        case stamp

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

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(L10n.t("friend_photo_booth_title"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    // Share button (only when photo taken)
                    if photoTaken, renderedImage != nil {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                // Photo frame area
                photoFrameContent
                    .offset(y: photoTaken ? 0 : photoDropOffset)
                    .rotationEffect(.degrees(photoTaken ? photoDropAngle : 0))
                    .animation(.interpolatingSpring(stiffness: 50, damping: 8).delay(0.15), value: photoTaken)

                Spacer()

                // Frame style picker
                if photoTaken {
                    frameStylePicker
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Shutter button
                bottomControls
                    .padding(.bottom, 20)
            }

            // Flash overlay
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

    // MARK: - Photo Frame

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
            // Photo area
            ZStack {
                // Warm cream photo background
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
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            // Bottom strip with handwriting
            VStack(spacing: 6) {
                Text(dateStampText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.75, green: 0.60, blue: 0.45))

                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.25))
                    .lineLimit(1)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        )
        .frame(width: 292)
    }

    private var filmStripFrame: some View {
        ZStack {
            // Film strip body
            VStack(spacing: 0) {
                filmPerforations
                    .padding(.vertical, 6)

                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)

                    photoSceneContent
                        .padding(8)
                }
                .frame(height: 260)

                filmPerforations
                    .padding(.vertical, 6)
            }
            .background(Color(red: 0.15, green: 0.14, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

            // Frame number overlay
            VStack {
                HStack {
                    Text("No. \(Int.random(in: 1...36))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.7))
                    Spacer()
                    Text(dateStampText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)

                Spacer()

                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.bottom, 30)
            }
        }
        .frame(width: 290, height: 330)
    }

    private var stampFrame: some View {
        ZStack {
            // Stamp perforated border
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

            VStack(spacing: 8) {
                // Stamp header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("StreetStamps")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(FigmaTheme.primary)
                            .textCase(.uppercase)
                            .tracking(1.5)

                        Text(L10n.t("friend_photo_stamp_subtitle"))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.gray)
                    }

                    Spacer()

                    // Stamp denomination
                    Text(dateStampShort)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(FigmaTheme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(FigmaTheme.secondary, lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Photo area with stamp-style inner border
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
                .frame(height: 230)
                .padding(.horizontal, 12)

                // Caption
                Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.25))
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 290, height: 340)
        .overlay(
            stampPerforationBorder
        )
    }

    // MARK: - Shared Scene Content

    private var photoSceneContent: some View {
        ZStack {
            // Scene background: soft gradient
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.93, blue: 0.88),
                    Color(red: 0.62, green: 0.85, blue: 0.80),
                    Color(red: 0.50, green: 0.76, blue: 0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Floor
            VStack {
                Spacer()
                Ellipse()
                    .fill(Color(red: 0.38, green: 0.65, blue: 0.58).opacity(0.35))
                    .frame(width: 200, height: 40)
                    .blur(radius: 4)
                    .offset(y: 8)
            }

            // Decorative confetti / sparkles
            confettiOverlay

            // Characters
            HStack(spacing: -10) {
                RobotRendererView(size: 100, face: .front, loadout: hostLoadout)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-5))

                RobotRendererView(size: 100, face: .front, loadout: visitorLoadout)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(5))
            }
            .offset(y: 16)

            // Heart / friendship indicator between them
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.50))
                .offset(y: -30)
                .shadow(color: Color(red: 1.0, green: 0.42, blue: 0.50).opacity(0.4), radius: 6, x: 0, y: 2)
        }
    }

    private var confettiOverlay: some View {
        ZStack {
            // Stars
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat.random(in: 8...14)))
                    .foregroundColor(
                        [Color.yellow, Color.orange, Color.pink, Color.mint, Color.cyan][i % 5].opacity(0.6)
                    )
                    .offset(
                        x: CGFloat([-90, 80, -60, 95, -30][i]),
                        y: CGFloat([-80, -60, 40, 50, -20][i])
                    )
            }
        }
    }

    // MARK: - Film Perforations

    private var filmPerforations: some View {
        HStack(spacing: 10) {
            ForEach(0..<15, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                    .frame(width: 10, height: 6)
            }
        }
    }

    // MARK: - Stamp Perforation Border

    private var stampPerforationBorder: some View {
        GeometryReader { geo in
            let size = geo.size
            let dotSize: CGFloat = 5
            let spacing: CGFloat = 10

            // Top edge
            HStack(spacing: spacing) {
                ForEach(0..<Int(size.width / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.92)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width / 2, y: -dotSize / 2)

            // Bottom edge
            HStack(spacing: spacing) {
                ForEach(0..<Int(size.width / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.92)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width / 2, y: size.height + dotSize / 2)

            // Left edge
            VStack(spacing: spacing) {
                ForEach(0..<Int(size.height / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.92)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: -dotSize / 2, y: size.height / 2)

            // Right edge
            VStack(spacing: spacing) {
                ForEach(0..<Int(size.height / (dotSize + spacing)), id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.92)).frame(width: dotSize, height: dotSize)
                }
            }
            .position(x: size.width + dotSize / 2, y: size.height / 2)
        }
    }

    // MARK: - Frame Style Picker

    private var frameStylePicker: some View {
        HStack(spacing: 16) {
            ForEach(PhotoFrameStyle.allCases, id: \.rawValue) { style in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedFrame = style
                    }
                    renderPhoto()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: style.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(style.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(selectedFrame == style ? .white : .white.opacity(0.45))
                    .frame(width: 60, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedFrame == style ? FigmaTheme.primary.opacity(0.8) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 40) {
            if photoTaken {
                // Retake
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        photoTaken = false
                        photoDropOffset = -600
                        renderedImage = nil
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .semibold))
                        Text(L10n.t("friend_photo_retake"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)

                // Save
                Button {
                    saveToPhotos()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 20, weight: .semibold))
                        Text(L10n.t("friend_photo_save"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
            } else {
                // Shutter button
                Button {
                    takePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)

                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                            .frame(width: 82, height: 82)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func takePhoto() {
        // Flash effect
        withAnimation(.easeIn(duration: 0.08)) {
            flashOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.3)) {
                flashOpacity = 0
            }
        }

        // Photo drops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            photoDropAngle = Double.random(in: -6...6)
            withAnimation {
                photoTaken = true
            }
            renderPhoto()
        }
    }

    @MainActor
    private func renderPhoto() {
        let exportView = photoExportView
            .frame(width: 320, height: 380)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 3
        renderedImage = renderer.uiImage
    }

    private func saveToPhotos() {
        guard let img = renderedImage else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    // MARK: - Export View (for rendering)

    private var photoExportView: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.94)

            VStack(spacing: 0) {
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

                    HStack(spacing: -10) {
                        RobotRendererView(size: 100, face: .front, loadout: hostLoadout)
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-5))
                        RobotRendererView(size: 100, face: .front, loadout: visitorLoadout)
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(5))
                    }
                    .offset(y: 16)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.50))
                        .offset(y: -30)
                }
                .frame(height: 280)

                VStack(spacing: 4) {
                    Text(dateStampText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.75, green: 0.60, blue: 0.45))
                    Text(String(format: L10n.t("friend_photo_caption_format"), hostName))
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.25))

                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                        Text("StreetStamps")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(FigmaTheme.primary.opacity(0.6))
                    .padding(.top, 4)
                }
                .frame(height: 80)
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
