import SwiftUI

struct JourneyPublishBanner: View {
    @EnvironmentObject private var publishStore: JourneyPublishStore

    var body: some View {
        switch publishStore.status {
        case .idle:
            EmptyView()
        case .sending(_, let title):
            bannerContent(
                icon: nil,
                message: String(format: L10n.t("publish_banner_sending_format"), title),
                style: .info,
                showSpinner: true
            )
        case .success(_, let title):
            bannerContent(
                icon: "checkmark.circle.fill",
                message: String(format: L10n.t("publish_banner_success_format"), title),
                style: .success,
                showSpinner: false
            )
        case .failed(_, let title, _):
            failedBanner(title: title)
        }
    }

    private func failedBanner(title: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                Text(String(format: L10n.t("publish_banner_failed_format"), title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 4)
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

    private enum BannerStyle {
        case info, success
    }

    private func bannerContent(icon: String?, message: String, style: BannerStyle, showSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showSpinner {
                ProgressView()
                    .scaleEffect(0.75)
                    .frame(width: 16, height: 16)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(style == .success ? .green : FigmaTheme.text)
            }
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
}
