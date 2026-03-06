import SwiftUI
import UIKit

struct FlippablePostcardView: View {
    let cityName: String
    let nickname: String
    let messageText: String
    let photoSource: PostcardPhotoSource
    let avatarLoadout: RobotLoadout
    @Binding var isFront: Bool
    var onLongPress: (() -> Void)? = nil

    private let cornerRadius: CGFloat = 22
    private let postcardAspectRatio: CGFloat = 3.0 / 2.0

    var body: some View {
        ZStack {
            PostcardBackFaceView(
                cityName: cityName,
                nickname: nickname,
                messageText: messageText,
                avatarLoadout: avatarLoadout,
                cornerRadius: cornerRadius
            )
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))

            PostcardFrontFaceView(
                cityName: cityName,
                nickname: nickname,
                photoSource: photoSource,
                avatarLoadout: avatarLoadout,
                cornerRadius: cornerRadius
            )
        }
        .rotation3DEffect(.degrees(isFront ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.58)
        .animation(.easeInOut(duration: 0.45), value: isFront)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            isFront.toggle()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            onLongPress?()
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 10)
        .aspectRatio(postcardAspectRatio, contentMode: .fit)
    }
}

struct PostcardFrontFaceView: View {
    let cityName: String
    let nickname: String
    let photoSource: PostcardPhotoSource
    let avatarLoadout: RobotLoadout
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            postcardImage

            LinearGradient(
                colors: [Color.black.opacity(0.00), Color.black.opacity(0.50)],
                startPoint: .center,
                endPoint: .bottom
            )

            PostcardIdentityRow(cityName: cityName, nickname: nickname, avatarLoadout: avatarLoadout)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(Color.white)
    }

    @ViewBuilder
    private var postcardImage: some View {
        switch photoSource {
        case .uiImage(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .localPath(let path):
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            Color(red: 0.93, green: 0.93, blue: 0.93)
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

    private var placeholder: some View {
        ZStack {
            Color(red: 0.92, green: 0.92, blue: 0.92)
            Image(systemName: "photo")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
        }
    }
}

struct PostcardBackFaceView: View {
    let cityName: String
    let nickname: String
    let messageText: String
    let avatarLoadout: RobotLoadout
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.99, green: 0.98, blue: 0.95))

            VStack(alignment: .leading, spacing: 14) {
                Text(messageText)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundColor(FigmaTheme.text)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .overlay(Color.black.opacity(0.12))

                PostcardIdentityRow(
                    cityName: cityName,
                    nickname: nickname,
                    avatarLoadout: avatarLoadout,
                    useDarkText: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PostcardIdentityRow: View {
    let cityName: String
    let nickname: String
    let avatarLoadout: RobotLoadout
    var useDarkText: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            RobotRendererView(size: 34, face: .front, loadout: avatarLoadout)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.88))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .semibold))
                    Text(cityName)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))

                Text(nickname)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(useDarkText ? FigmaTheme.text : .white)
            .shadow(color: useDarkText ? .clear : Color.black.opacity(0.45), radius: 2, x: 0, y: 1)

            Spacer(minLength: 0)
        }
    }
}

enum PostcardPhotoSource {
    case uiImage(UIImage)
    case localPath(String)
    case remoteURL(String)
    case none
}
