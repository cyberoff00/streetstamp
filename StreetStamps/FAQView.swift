import SwiftUI

struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

enum FAQContent {
    static func items() -> [FAQItem] {
        [
            FAQItem(
                id: "overview",
                question: L10n.t("faq_q_overview"),
                answer: L10n.t("faq_a_overview")
            ),
            FAQItem(
                id: "route_recording",
                question: L10n.t("faq_q_route_recording"),
                answer: L10n.t("faq_a_route_recording")
            ),
            FAQItem(
                id: "track_accuracy",
                question: L10n.t("faq_q_track_accuracy"),
                answer: L10n.t("faq_a_track_accuracy")
            ),
            FAQItem(
                id: "battery",
                question: L10n.t("faq_q_battery"),
                answer: L10n.t("faq_a_battery")
            ),
            FAQItem(
                id: "data_storage",
                question: L10n.t("faq_q_data_storage"),
                answer: L10n.t("faq_a_data_storage")
            ),
            FAQItem(
                id: "phone_migration",
                question: L10n.t("faq_q_phone_migration"),
                answer: L10n.t("faq_a_phone_migration")
            ),
            FAQItem(
                id: "icloud_sync",
                question: L10n.t("faq_q_icloud_sync"),
                answer: L10n.t("faq_a_icloud_sync")
            ),
            FAQItem(
                id: "gpx_import",
                question: L10n.t("faq_q_gpx_import"),
                answer: L10n.t("faq_a_gpx_import")
            ),
            FAQItem(
                id: "city_unlock",
                question: L10n.t("faq_q_city_unlock"),
                answer: L10n.t("faq_a_city_unlock")
            ),
            FAQItem(
                id: "postcard_rules",
                question: L10n.t("faq_q_postcard_rules"),
                answer: L10n.t("faq_a_postcard_rules")
            ),
            FAQItem(
                id: "location_permission",
                question: L10n.t("faq_q_location_permission"),
                answer: L10n.t("faq_a_location_permission")
            )
        ]
    }
}

struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedID: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("faq_subtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    ForEach(FAQContent.items()) { item in
                        faqCard(item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: L10n.t("faq_title"),
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

    private func faqCard(_ item: FAQItem) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedID = expandedID == item.id ? nil : item.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(FigmaTheme.primary)
                        .frame(width: 20)
                        .padding(.top, 2)

                    Text(item.question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: expandedID == item.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.42))
                        .padding(.top, 3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if expandedID == item.id {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    Text(item.answer)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.text.opacity(0.78))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .figmaSurfaceCard(radius: 16)
        }
        .buttonStyle(.plain)
    }
}
