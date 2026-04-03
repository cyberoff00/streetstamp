import SwiftUI

enum AboutUsContent {
    struct Section: Equatable {
        let title: String
        let paragraphs: [String]
    }

    static let title = L10n.t("about_us_title")
    static let location = L10n.t("about_us_location")

    static var sections: [Section] {[
        Section(
            title: "",
            paragraphs: [
                L10n.t("about_us_intro"),
                L10n.t("about_us_walking"),
                L10n.t("about_us_gamification"),
                L10n.t("about_us_ai_era")
            ]
        ),
        Section(
            title: L10n.t("about_postscript"),
            paragraphs: [
                L10n.t("about_us_traveler_needs")
            ]
        ),
        Section(
            title: L10n.t("about_us_traveler_needs"),
            paragraphs: [
                L10n.t("about_us_traveler_needs_content")
            ]
        ),
        Section(
            title: L10n.t("about_us_cyber_dog_title"),
            paragraphs: [
                L10n.t("about_us_cyber_dog_content")
            ]
        )
    ]}
}

struct AboutUsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock

                divider
                    .padding(.vertical, 28)

                articleBody
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: AboutUsContent.title,
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
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("about_worldo_header"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundColor(Color.black.opacity(0.48))

            VStack(alignment: .leading, spacing: 8) {
                Text(AboutUsContent.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(UITheme.softBlack)

                Text(AboutUsContent.location)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.26, green: 0.30, blue: 0.35))

                Text(L10n.t("brand_tagline_journey_memory"))
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
            }

            HStack(spacing: 10) {
                metaChip(icon: "location", text: AboutUsContent.location)
                metaChip(icon: "text.book.closed", text: L10n.t("brand_wordmark").capitalized)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AboutUsContent.sections.enumerated()), id: \.offset) { index, section in
                if index == 0 {
                    bodyParagraphGroup(section.paragraphs)
                } else if section.title == L10n.t("about_postscript") {
                    asideSection
                        .padding(.top, 48)
                }
            }
        }
    }

    private var asideSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.key("about_postscript"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.softBlack)

            ForEach(Array(AboutUsContent.sections.dropFirst(2).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(red: 0.26, green: 0.30, blue: 0.35))
                            .padding(.top, section.title == L10n.t("about_us_traveler_needs") ? 6 : 0)
                    }

                    bodyParagraphGroup(section.paragraphs)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func bodyParagraphGroup(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Color.black.opacity(0.68))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }
}
