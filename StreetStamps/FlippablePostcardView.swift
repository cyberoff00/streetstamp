import SwiftUI
import UIKit

struct FlippablePostcardView: View {
    let cityName: String
    let nickname: String
    let messageText: String
    let photoSource: PostcardPhotoSource
    let avatarLoadout: RobotLoadout
    let sentDate: Date?
    let showFrontOverlays: Bool
    @Binding var isFront: Bool
    var onLongPress: (() -> Void)? = nil

    init(
        cityName: String,
        nickname: String,
        messageText: String,
        photoSource: PostcardPhotoSource,
        avatarLoadout: RobotLoadout,
        isFront: Binding<Bool>,
        sentDate: Date? = nil,
        showFrontOverlays: Bool = true,
        onLongPress: (() -> Void)? = nil
    ) {
        self.cityName = cityName
        self.nickname = nickname
        self.messageText = messageText
        self.photoSource = photoSource
        self.avatarLoadout = avatarLoadout
        self.sentDate = sentDate
        self.showFrontOverlays = showFrontOverlays
        self._isFront = isFront
        self.onLongPress = onLongPress
    }

    @State private var showFrontFace = true
    private let cornerRadius: CGFloat = 18
    private let postcardAspectRatio: CGFloat = 3.0 / 2.0
    private let flipDuration: Double = 0.45

    var body: some View {
        ZStack {
            if showFrontFace {
                PostcardFrontFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    photoSource: photoSource,
                    avatarLoadout: avatarLoadout,
                    cornerRadius: cornerRadius,
                    showOverlays: showFrontOverlays
                )
            } else {
                PostcardBackFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    messageText: messageText,
                    avatarLoadout: avatarLoadout,
                    sentDate: sentDate,
                    cornerRadius: cornerRadius
                )
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(isFront ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.58)
        .animation(.easeInOut(duration: flipDuration), value: isFront)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            isFront.toggle()
        }
        .onChange(of: isFront) { _, newValue in
            // Switch visible face at animation midpoint (card is edge-on, switch is invisible)
            DispatchQueue.main.asyncAfter(deadline: .now() + flipDuration / 2) {
                showFrontFace = newValue
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            onLongPress?()
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 10)
        .aspectRatio(postcardAspectRatio, contentMode: .fit)
    }
}

// MARK: - Front Face

struct PostcardFrontFaceView: View {
    let cityName: String
    let nickname: String
    let photoSource: PostcardPhotoSource
    let avatarLoadout: RobotLoadout
    let cornerRadius: CGFloat
    var showOverlays: Bool = true

    var body: some View {
        ZStack {
            // Photo background
            postcardImage

            if showOverlays {
                // Vignette overlay
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0), location: 0.3),
                        .init(color: Color.black.opacity(0.55), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top-right stamp
                VStack {
                    HStack {
                        Spacer()
                        postcardStamp
                    }
                    Spacer()
                }
                .padding(12)

                // Bottom info
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("postcard_greetings_from"))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.7))

                            Text(cityName.uppercased())
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        }
                        Spacer()
                        Text(nickname)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
        )
    }

    private var postcardStamp: some View {
        VStack(spacing: 2) {
            RobotRendererView(size: 28, face: .front, loadout: avatarLoadout)
                .frame(width: 28, height: 28)

            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 28, height: 1)
        }
        .padding(5)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
                .foregroundColor(Color.black.opacity(0.15))
        )
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    @ViewBuilder
    private var postcardImage: some View {
        GeometryReader { geo in
            switch photoSource {
            case .uiImage(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            case .localPath(let path):
                if let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    placeholder
                }
            case .remoteURL(let raw):
                if let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            placeholder
                        case .empty:
                            ZStack {
                                Color(red: 0.95, green: 0.94, blue: 0.92)
                                ProgressView()
                            }
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            case .none:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 0.88),
                    Color(red: 0.88, green: 0.85, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color.black.opacity(0.2))
        }
    }
}

// MARK: - Back Face (classic postcard layout)

struct PostcardBackFaceView: View {
    let cityName: String
    let nickname: String
    let messageText: String
    let avatarLoadout: RobotLoadout
    let sentDate: Date?
    let cornerRadius: CGFloat

    init(
        cityName: String,
        nickname: String,
        messageText: String,
        avatarLoadout: RobotLoadout,
        sentDate: Date? = nil,
        cornerRadius: CGFloat
    ) {
        self.cityName = cityName
        self.nickname = nickname
        self.messageText = messageText
        self.avatarLoadout = avatarLoadout
        self.sentDate = sentDate
        self.cornerRadius = cornerRadius
    }

    private let creamBg = Color(red: 0.99, green: 0.975, blue: 0.94)
    private let inkColor = Color(red: 0.18, green: 0.16, blue: 0.14)
    private let lightInk = Color(red: 0.55, green: 0.50, blue: 0.45)
    private let ruleColor = Color(red: 0.82, green: 0.78, blue: 0.72)

    var body: some View {
        ZStack {
            // Paper background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(creamBg)

            HStack(spacing: 0) {
                // Left: message area
                messageArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Center divider
                Rectangle()
                    .fill(ruleColor)
                    .frame(width: 1)
                    .padding(.vertical, 16)

                // Right: address/identity area
                identityArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var messageArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(messageText)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(inkColor)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 4)

            // Sender signature
            HStack(spacing: 0) {
                Spacer()
                Text("— \(nickname)")
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(lightInk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var identityArea: some View {
        VStack(spacing: 0) {
            // Stamp area (top-right)
            HStack {
                Spacer()
                stampView
            }
            .padding(.top, 10)
            .padding(.trailing, 10)

            Spacer()

            // Address lines
            VStack(alignment: .leading, spacing: 6) {
                // City line
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                    Text(cityName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(inkColor)
                        .lineLimit(1)
                }

                // Ruled lines
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(ruleColor.opacity(0.6))
                        .frame(height: 0.5)
                }

                // Date
                if let sentDate {
                    Text(sentDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(lightInk)
                } else {
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(lightInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }

    private var stampView: some View {
        VStack(spacing: 3) {
            RobotRendererView(size: 36, face: .front, loadout: avatarLoadout)
                .frame(width: 36, height: 36)

            Text(L10n.t("postcard_brand_street"))
                .font(.system(size: 5, weight: .heavy, design: .monospaced))
                .foregroundColor(lightInk)
            Text(L10n.t("postcard_brand_stamps"))
                .font(.system(size: 5, weight: .heavy, design: .monospaced))
                .foregroundColor(lightInk)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(creamBg)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                )
                .foregroundColor(ruleColor)
        )
    }
}

// MARK: - Photo Source

enum PostcardPhotoSource {
    case uiImage(UIImage)
    case localPath(String)
    case remoteURL(String)
    case none
}
