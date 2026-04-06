import SwiftUI

private enum WorldoPage: Int, CaseIterable, Identifiable {
    case cities
    case memories

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cities: return L10n.t("collection_segment_cities")
        case .memories: return L10n.t("tab_memory")
        }
    }
}

struct CollectionTabView: View {
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator
    @State private var page: WorldoPage = .cities
    @StateObject private var memoryFilterState = MemoryFilterState()
    @State private var cachedSortedJourneys: [JourneyRoute] = []
    @State private var cachedActivityTags: [String] = []
    @State private var activeJourneyDetail: JourneyMemoryDetailDestination? = nil

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                pagePicker
                pager
            }
        }
        .overlay(alignment: .bottom) {
            if page == .cities && cityCache.cachedCities.count == 1 && onboardingGuide.shouldShowHint(.cityCardCollect) && !onboardingGuide.shouldShowHint(.journeySavedToMemory) {
                ContextualHintBar(
                    icon: "map",
                    message: L10n.t("hint_city_card_collect"),
                    onDismiss: { onboardingGuide.dismissHint(.cityCardCollect) }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .onReceive(flow.$requestedCollectionPage) { rawPage in
            guard let rawPage, let target = WorldoPage(rawValue: rawPage) else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                page = target
            }
            flow.clearRequestedCollectionPage()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: page)
        .onChange(of: page) { value in
            if value == .memories {
                onboardingGuide.advance(.openMemory)
            }
        }
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
        .navigationDestination(item: $activeJourneyDetail) { destination in
            JourneyMemoryDetailView(
                journey: destination.journey,
                memories: destination.memories,
                cityName: destination.cityName,
                countryName: destination.countryName,
                readOnly: destination.readOnly,
                friendLoadout: destination.friendLoadout
            )
            .environmentObject(store)
        }
        .onAppear { refreshDerivedJourneyData() }
        .onChange(of: store.journeys.count) { _, _ in refreshDerivedJourneyData() }
        .onChange(of: store.metadataRevision) { _, _ in refreshDerivedJourneyData() }
    }

    private var availableActivityTags: [String] { cachedActivityTags }
    private var allMemoryJourneys: [JourneyRoute] { cachedSortedJourneys }

    private func refreshDerivedJourneyData() {
        cachedSortedJourneys = store.journeys
            .sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) }
        let tags = cachedSortedJourneys.compactMap { j -> String? in
            let tag = (j.activityTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        }
        cachedActivityTags = Array(Set(tags)).sorted()
    }

    private var header: some View {
        UnifiedTabPageHeader(title: L10n.t("collection_page_title"), titleLevel: .primary, horizontalPadding: 18, topPadding: 14, bottomPadding: 12) {
            Color.clear
        } trailing: {
            if page == .memories {
                MemoryFilterControls(
                    filterState: memoryFilterState,
                    availableActivityTags: availableActivityTags,
                    allJourneys: allMemoryJourneys
                )
            } else {
                Color.clear
            }
        }
    }

    private var pagePicker: some View {
        HStack {
            ForEach(WorldoPage.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        page = item
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(page == item ? FigmaTheme.primary : Color.clear)

                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(page == item ? .white : .black.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .appFullSurfaceTapTarget(.roundedRect(17))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var pager: some View {
        ZStack {
            if page == .cities {
                CityStampLibraryView(
                    showHeader: false
                )
                .transition(.move(edge: .leading))
            } else {
                JourneyMemoryMainView(
                    hideLeadingControl: true,
                    showHeader: false,
                    filterState: memoryFilterState,
                    onSelectJourney: { activeJourneyDetail = $0 }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    if value.translation.width < -30, page == .cities {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            page = .memories
                        }
                    } else if value.translation.width > 30, page == .memories {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            page = .cities
                        }
                    }
                }
        )
    }
}
