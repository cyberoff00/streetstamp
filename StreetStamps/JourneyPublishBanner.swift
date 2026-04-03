import SwiftUI

struct JourneyPublishBanner: View {
    @EnvironmentObject private var publishStore: JourneyPublishStore

    var body: some View {
        switch publishStore.status {
        case .idle:
            EmptyView()
        case .sending(_, let title):
            bannerContent(
                leading: { AnyView(ProgressView().tint(FigmaTheme.subtext).scaleEffect(0.8)) },
                message: String(format: L10n.t("publish_banner_sending_format"), title),
                style: .info
            )
        case .success(_, let title):
            bannerContent(
                leading: { AnyView(Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)) },
                message: String(format: L10n.t("publish_banner_success_format"), title),
                style: .success
            )
        case .failed(_, let title, let errorMessage):
            failedBanner(title: title, errorMessage: errorMessage)
        }
    }

    private enum BannerStyle { case info, success }

    private func bannerContent(
        leading: () -> AnyView,
        message: String,
        style: BannerStyle
    ) -> some View {
        HStack(spacing: 8) {
            leading()
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(style == .success ? Color(red: 0.93, green: 0.98, blue: 0.94) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style == .success ? Color.green.opacity(0.2) : FigmaTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private func failedBanner(title: String, errorMessage: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L10n.t("publish_banner_failed_format"), title))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .lineLimit(1)
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundColor(FigmaTheme.subtext)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    publishStore.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(FigmaTheme.subtext)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button {
                    publishStore.retry()
                } label: {
                    Text(L10n.t("publish_banner_retry"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    publishStore.fallbackToPrivate()
                } label: {
                    Text(L10n.t("publish_banner_save_private"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .background(Color(red: 1.0, green: 0.95, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }
}
