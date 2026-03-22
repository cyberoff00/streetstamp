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
    @State private var page: WorldoPage = .cities
    @StateObject private var memoryFilterState = MemoryFilterState()

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                pagePicker
                pager
            }
        }
        .onChange(of: page) { value in
            if value == .memories {
                onboardingGuide.advance(.openMemory)
            }
        }
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
    }

    private var availableActivityTags: [String] {
        let tags = store.journeys.compactMap { j -> String? in
            let tag = (j.activityTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        }
        return Array(Set(tags)).sorted()
    }

    private var allMemoryJourneys: [JourneyRoute] {
        store.journeys
            .sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) }
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
                    withAnimation(.easeInOut(duration: 0.22)) {
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
        TabView(selection: $page) {
            CityStampLibraryView(
                showSidebar: .constant(false),
                usesSidebarHeader: false,
                showHeader: false
            )
            .tag(WorldoPage.cities)

            JourneyMemoryMainView(
                showSidebar: .constant(false),
                usesSidebarHeader: false,
                hideLeadingControl: true,
                showHeader: false,
                filterState: memoryFilterState
            )
            .tag(WorldoPage.memories)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}
