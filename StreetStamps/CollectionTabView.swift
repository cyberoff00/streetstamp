import SwiftUI

private enum CollectionSegment: String, CaseIterable, Identifiable {
    case cities
    case journeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cities: return "Cities"
        case .journeys: return "Journeys"
        }
    }
}

struct CollectionTabView: View {
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
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        UnifiedTabPageHeader(title: "COLLECTION", horizontalPadding: 18, topPadding: 14, bottomPadding: 12) {
            Color.clear
        } trailing: {
            Color.clear
        }
    }

    private var segmentPicker: some View {
        HStack {
            Picker("Collection", selection: $segment) {
                ForEach(CollectionSegment.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
