import SwiftUI

struct JourneyLiker: Identifiable {
    let id: String
    let name: String
    let likedAt: Date
}

enum JourneyVisibilitySheetAccentStyle: Equatable {
    case neutral
    case accent
}

struct JourneyVisibilitySheetOptionPresentation: Equatable {
    let visibility: JourneyVisibility
    let symbolName: String
    let eyebrow: String
    let title: String
    let description: String
    let accentStyle: JourneyVisibilitySheetAccentStyle
}

enum JourneyVisibilitySheetPresentation {
    static let optionPresentations: [JourneyVisibilitySheetOptionPresentation] = [
        JourneyVisibilitySheetOptionPresentation(
            visibility: .private,
            symbolName: "lock.fill",
            eyebrow: "PRIVATE",
            title: L10n.t("visibility_private"),
            description: L10n.t("journey_visibility_private_description"),
            accentStyle: .neutral
        ),
        JourneyVisibilitySheetOptionPresentation(
            visibility: .friendsOnly,
            symbolName: "person.2.fill",
            eyebrow: "FRIENDS",
            title: L10n.t("visibility_friends_only"),
            description: L10n.t("journey_visibility_friends_description"),
            accentStyle: .accent
        )
    ]
}

enum JourneyDetailSheetRoutePresentation: String, Equatable, Identifiable {
    case visibility
    case likes

    var id: String { rawValue }

    static func primaryRoute(forLikesCount likesCount: Int) -> Self {
        likesCount > 0 ? .likes : .visibility
    }
}

struct JourneyVisibilitySheet: View {
    let journey: JourneyRoute
    @Binding var pendingVisibility: JourneyVisibility
    let isSubmitting: Bool
    let onApply: () -> Void

    private var canApply: Bool {
        !isSubmitting
    }

    private var selectedPresentation: JourneyVisibilitySheetOptionPresentation? {
        JourneyVisibilitySheetPresentation.optionPresentations.first { $0.visibility == pendingVisibility }
    }

    var body: some View {
        JourneySheetScaffold(
            title: L10n.t("journey_change_visibility"),
            subtitle: String(format: L10n.t("journey_current_visibility_format"), journey.visibility.localizedTitle)
        ) {
            lightweightVisibilityToggle

            if let selectedPresentation {
                Text(selectedPresentation.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .lineSpacing(1.5)
                    .padding(.horizontal, 2)
            }

            Button(action: onApply) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(L10n.t("journey_confirm_change"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canApply ? UITheme.softBlack : Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .appFullSurfaceTapTarget(.roundedRect(16))
            }
            .disabled(!canApply)
            .buttonStyle(.plain)
        }
    }

    private var lightweightVisibilityToggle: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(pendingVisibility == .friendsOnly ? UITheme.accent.opacity(0.12) : Color.black.opacity(0.05))
                    .frame(width: 34, height: 34)

                Image(systemName: pendingVisibility == .friendsOnly ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(pendingVisibility == .friendsOnly ? UITheme.accent : UITheme.softBlack)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("journey_change_visibility"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(UITheme.softBlack)

                Text(pendingVisibility.localizedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: friendsVisibilityBinding)
                .labelsHidden()
                .tint(UITheme.accent)
                .scaleEffect(0.88)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var friendsVisibilityBinding: Binding<Bool> {
        Binding(
            get: { pendingVisibility == .friendsOnly },
            set: { isOn in
                pendingVisibility = isOn ? .friendsOnly : .private
            }
        )
    }
}

struct JourneySheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            FigmaTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(UITheme.softBlack)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                content

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct JourneyLikesSheet: View {
    let journey: JourneyRoute
    let displayCityName: String
    let likers: [JourneyLiker]
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onEditVisibility: () -> Void

    private var title: String {
        journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (journey.customTitle ?? "")
            : displayCityName
    }

    var body: some View {
        JourneySheetScaffold(title: L10n.t("journey_likes_title"), subtitle: title) {
            Button(action: onEditVisibility) {
                HStack {
                    Text(L10n.t("journey_change_permission"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(UITheme.softBlack)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .appFullSurfaceTapTarget(.roundedRect(16))
            }
            .buttonStyle(.plain)

            if isLoading {
                statusCard(icon: "clock", text: L10n.t("journey_likes_loading"))
            } else if let errorMessage, !errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: L10n.t("journey_loading_failed_format"), errorMessage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.82))
                    Button(L10n.t("retry"), action: onRetry)
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(UITheme.softBlack)
                        .appFullSurfaceTapTarget(.rectangle)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(0.10), lineWidth: 1)
                )
            } else if likers.isEmpty {
                statusCard(icon: "heart", text: L10n.t("journey_no_likes_yet"))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(likers) { liker in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        Text(String(liker.name.prefix(1)).uppercased())
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(UITheme.softBlack.opacity(0.75))
                                    }

                                Text(liker.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(UITheme.softBlack)
                                Spacer()
                                Text(Self.timeText(from: liker.likedAt))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.subtext)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .background(Color.black.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func statusCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            if icon == "clock" {
                ProgressView()
                    .scaleEffect(0.9)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(FigmaTheme.subtext)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private static func timeText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
