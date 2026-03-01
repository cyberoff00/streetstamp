import SwiftUI

struct PostcardPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var postcardCenter: PostcardCenter

    let friendID: String
    let friendName: String
    let selectedCityID: String
    let selectedCityName: String
    let messageText: String
    let localImagePath: String
    let selectedImage: UIImage?
    let allowedCityIDs: [String]

    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            postcardCard

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
        VStack(spacing: 0) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(FigmaTheme.border)
                    .frame(height: 220)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(selectedCityName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                Text("\(L10n.t("postcard_to_prefix"))\(friendName)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
                Text(messageText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(FigmaTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private func sendNow() async {
        isSending = true
        errorText = nil
        defer { isSending = false }

        let draft = postcardCenter.createDraft(
            toUserID: friendID,
            cityID: selectedCityID,
            cityName: selectedCityName,
            photoLocalPath: localImagePath,
            message: messageText
        )

        await postcardCenter.enqueueSend(
            draftID: draft.draftID,
            token: sessionStore.currentAccessToken,
            allowedCityIDs: allowedCityIDs
        )

        if let latest = postcardCenter.drafts.first(where: { $0.draftID == draft.draftID }), latest.status == .sent {
            dismiss()
            dismiss()
            return
        }

        if let latest = postcardCenter.drafts.first(where: { $0.draftID == draft.draftID }) {
            errorText = latest.lastError ?? L10n.t("postcard_send_failed")
        } else {
            errorText = L10n.t("postcard_send_failed")
        }
    }
}
