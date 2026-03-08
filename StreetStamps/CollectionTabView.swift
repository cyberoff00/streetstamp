import SwiftUI

private enum CollectionSegment: String, CaseIterable, Identifiable {
    case cities
    case journeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cities: return L10n.t("collection_segment_cities")
        case .journeys: return L10n.t("collection_segment_journeys")
        }
    }
}

struct CollectionTabView: View {
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @State private var segment: CollectionSegment = .cities

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                segmentPicker

                Group {
                    switch segment {
                    case .cities:
                        CityStampLibraryView(
                            showSidebar: .constant(false),
                            usesSidebarHeader: false,
                            showHeader: false
                        )
                    case .journeys:
                        MyJourneysView(showHeader: false)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if onboardingGuide.isCurrent(.openJourneysSegment) {
                OnboardingCoachCard(
                    message: OnboardingGuideStore.Step.openJourneysSegment.message,
                    actionTitle: OnboardingGuideStore.Step.openJourneysSegment.actionTitle,
                    onAction: {
                        segment = .journeys
                        onboardingGuide.advance(.openJourneysSegment)
                    },
                    onLater: { onboardingGuide.pauseForLater() },
                    onSkip: { onboardingGuide.skipAll() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 96)
            }
        }
        .onChange(of: segment) { value in
            if value == .journeys {
                onboardingGuide.advance(.openJourneysSegment)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        UnifiedTabPageHeader(title: L10n.t("collection_title"), titleLevel: .primary, horizontalPadding: 18, topPadding: 14, bottomPadding: 12) {
            Color.clear
        } trailing: {
            Color.clear
        }
    }

    private var segmentPicker: some View {
        HStack {
            Picker(L10n.t("collection_title"), selection: $segment) {
                ForEach(CollectionSegment.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .overlay {
                if onboardingGuide.isCurrent(.openJourneysSegment) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black, lineWidth: 2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
