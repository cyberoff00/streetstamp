import SwiftUI
import UIKit

struct PostcardPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var postcardCenter: PostcardCenter
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    let friendID: String
    let friendName: String
    let selectedCityID: String
    let selectedCityName: String
    let messageText: String
    let localImagePath: String
    let selectedImage: UIImage?
    let allowedCityIDs: [String]
    let onSent: (() -> Void)?

    @State private var isSending = false
    @State private var errorText: String?
    @State private var isFrontShowing = true
    @State private var saveToastText: String?

    var body: some View {
        VStack(spacing: 20) {
            postcardCard

            if let saveToastText {
                Text(saveToastText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
            }

            Button {
                Task {
                    await sendNow()
                }
            } label: {
                Text(isSending ? L10n.t("postcard_sending") : L10n.t("postcard_send"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isSending ? FigmaTheme.primary.opacity(0.45) : FigmaTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSending)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationTitle(L10n.t("postcard_preview_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var postcardCard: some View {
        FlippablePostcardView(
            cityName: selectedCityName,
            nickname: senderDisplayName.uppercased(),
            messageText: messageText,
            photoSource: photoSource,
            avatarLoadout: AvatarLoadoutStore.load(),
            isFront: $isFrontShowing,
            onLongPress: {
                saveCurrentFaceToPhotos()
            }
        )
    }

    private var photoSource: PostcardPhotoSource {
        if let selectedImage {
            return .uiImage(selectedImage)
        }
        let trimmedPath = localImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? .none : .localPath(trimmedPath)
    }

    private var senderDisplayName: String {
        let normalized = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "EXPLORER" : normalized
    }

    private func sendNow() async {
        isSending = true
        errorText = nil
        defer { isSending = false }

        let photoPathForSend = composedPostcardImagePath() ?? localImagePath
        let draft = postcardCenter.createDraft(
            toUserID: friendID,
            cityID: selectedCityID,
            cityName: selectedCityName,
            photoLocalPath: photoPathForSend,
            message: messageText
        )

        await postcardCenter.enqueueSend(
            draftID: draft.draftID,
            token: sessionStore.currentAccessToken,
            allowedCityIDs: allowedCityIDs
        )

        if let latest = postcardCenter.drafts.first(where: { $0.draftID == draft.draftID }), latest.status == .sent {
            dismiss()
            DispatchQueue.main.async {
                onSent?()
            }
            return
        }

        if let latest = postcardCenter.drafts.first(where: { $0.draftID == draft.draftID }) {
            errorText = latest.lastError ?? L10n.t("postcard_send_failed")
        } else {
            errorText = L10n.t("postcard_send_failed")
        }
    }

    private func composedPostcardImagePath() -> String? {
        guard #available(iOS 16.0, *),
              let image = renderFaceImage(isFront: true),
              let data = image.jpegData(compressionQuality: 0.92) else {
            return nil
        }

        let fileName = "postcard_render_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }

    private func saveCurrentFaceToPhotos() {
        guard #available(iOS 16.0, *), let image = renderFaceImage(isFront: isFrontShowing) else {
            saveToastText = "保存失败"
            clearSaveToastSoon()
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saveToastText = isFrontShowing ? "已保存明信片正面" : "已保存明信片反面"
        clearSaveToastSoon()
    }

    @available(iOS 16.0, *)
    private func renderFaceImage(isFront: Bool) -> UIImage? {
        let width: CGFloat = 1080
        let height: CGFloat = width / (3.0 / 2.0)

        let faceView: AnyView
        if isFront {
            faceView = AnyView(
                PostcardFrontFaceView(
                    cityName: selectedCityName,
                    nickname: senderDisplayName.uppercased(),
                    photoSource: photoSource,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    cornerRadius: 22
                )
            )
        } else {
            faceView = AnyView(
                PostcardBackFaceView(
                    cityName: selectedCityName,
                    nickname: senderDisplayName.uppercased(),
                    messageText: messageText,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    cornerRadius: 22
                )
            )
        }

        let renderView = faceView
            .frame(width: width, height: height)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func clearSaveToastSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saveToastText = nil
        }
    }
}
