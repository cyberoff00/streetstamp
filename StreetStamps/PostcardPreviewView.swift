import SwiftUI
import UIKit
import ImageIO

struct PostcardPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var postcardCenter: PostcardCenter
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    let friendID: String
    let friendName: String
    let selectedCityID: String
    let selectedCityName: String
    let selectedCityJourneyCount: Int
    let messageText: String
    let localImagePath: String
    let selectedImage: UIImage?
    let allowedCityIDs: [String]
    let onSent: (() -> Void)?

    @State private var isSending = false
    @State private var errorText: String?
    @State private var isFrontShowing = true
    @State private var saveToastText: String?
    @State private var downsampledImage: UIImage?
    @State private var sentSuccessfully = false
    @State private var sidebarHideToken = "\(PostcardSidebarVisibilityScope.preview.token)-\(UUID().uuidString)"

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

            if sentSuccessfully {
                // Inline success state – replaces the send button
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(L10n.t("postcard_sent_success_title"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onSent?()
                            NotificationCenter.default.post(name: .postcardSentGoToInbox, object: nil)
                        }
                    } label: {
                        Text(L10n.t("postcard_go_to_sent_box"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FigmaTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onSent?()
                        }
                    } label: {
                        Text(L10n.t("cancel"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    .buttonStyle(.plain)
                }
            } else {
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
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(FigmaTheme.background.ignoresSafeArea())
        .onAppear {
            guard PostcardSidebarVisibilityScope.preview.hidesGlobalSidebarButton else { return }
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            guard PostcardSidebarVisibilityScope.preview.hidesGlobalSidebarButton else { return }
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: L10n.t("postcard_preview_title"),
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 18,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { prepareDownsampledImage() }
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
        if let downsampledImage {
            return .uiImage(downsampledImage)
        }
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

        // Send the raw (downsampled) photo – NOT the composed postcard image.
        // The recipient's client reconstructs the full postcard from metadata.
        let photoPathForSend = downsampledPhotoPath() ?? localImagePath
        let draft = postcardCenter.createDraft(
            toUserID: friendID,
            toDisplayName: friendName,
            cityID: selectedCityID,
            cityName: selectedCityName,
            photoLocalPath: photoPathForSend,
            message: messageText
        )

        postcardCenter.enqueueSendInBackground(
            draftID: draft.draftID,
            token: sessionStore.currentAccessToken,
            allowedCityIDs: allowedCityIDs,
            cityJourneyCount: selectedCityJourneyCount
        )
        isSending = false
        dismiss()
    }

    /// Save the downsampled raw photo to a temp file for upload.
    private func downsampledPhotoPath() -> String? {
        guard let image = downsampledImage ?? selectedImage,
              let data = MediaUploadPreparation.preparePostcardUploadData(image: image) else {
            return nil
        }
        let fileName = "postcard_photo_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }

    private func composedPostcardImagePath() -> String? {
        guard #available(iOS 16.0, *),
              let image = renderFaceImage(isFront: true),
              let data = image.jpegData(compressionQuality: 0.82) else {
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
        let width: CGFloat = 540
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
                    sentDate: nil,
                    cornerRadius: 22
                )
            )
        }

        let renderView = faceView
            .frame(width: width, height: height)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func clearSaveToastSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saveToastText = nil
        }
    }

    // MARK: - Image Downsampling

    /// Max pixel dimension for the postcard photo (2x render width).
    private static let maxImageDimension: CGFloat = 1080

    private func prepareDownsampledImage() {
        guard downsampledImage == nil else { return }
        if let selectedImage {
            let maxDim = max(selectedImage.size.width, selectedImage.size.height)
            guard maxDim > Self.maxImageDimension else {
                downsampledImage = selectedImage
                return
            }
            if let data = selectedImage.jpegData(compressionQuality: 1.0) {
                downsampledImage = Self.downsample(data: data, maxDimension: Self.maxImageDimension)
            }
        } else {
            let trimmed = localImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let url = URL(fileURLWithPath: trimmed)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            downsampledImage = Self.downsample(url: url, maxDimension: Self.maxImageDimension)
        }
    }

    /// Efficient thumbnail-style decode via CGImageSource – only decodes the pixels needed.
    private static func downsample(url: URL, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        return downsample(source: source, maxDimension: maxDimension)
    }

    private static func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        return downsample(source: source, maxDimension: maxDimension)
    }

    private static func downsample(source: CGImageSource, maxDimension: CGFloat) -> UIImage? {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
