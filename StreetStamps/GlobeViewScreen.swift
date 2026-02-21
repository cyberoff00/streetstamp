//
//  GlobeViewScreen.swift
//  StreetStamps
//
//  Created by Claire Yang on 26/01/2026.
//

import SwiftUI
import UIKit

private struct GlobeShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Standalone page for Sidebar tab: Globe View
struct GlobeViewScreen: View {
    @Binding var showSidebar: Bool
    var externalJourneys: [JourneyRoute]? = nil
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var dummyPresented: Bool = true
    @State private var shareItem: GlobeShareImageItem? = nil

    var body: some View {
        let journeysForRender = externalJourneys ?? store.journeys
        ZStack {
            MapboxGlobeView(
                isPresented: $dummyPresented,
                journeys: journeysForRender,
                showsCloseButton: false
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topHeader
                Spacer()
                bottomSummaryCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 70)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
    }

    private var topHeader: some View {
        HStack {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            Spacer()

            Text("GLOBAL VIEW")
                .appHeaderStyle()
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Circle())
            }
        }
    }

    private var bottomSummaryCard: some View {
        let journeys = externalJourneys ?? store.journeys
        let totalJourneys = journeys.count
        let totalMemories = journeys.reduce(0) { $0 + $1.memories.count }
        let totalDistanceMeters = journeys.reduce(0.0) { partial, journey in
            let d = journey.distance
            return partial + ((d.isFinite && d > 0) ? d : 0)
        }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let distanceKmDisplay = max(0, Int(totalDistanceKm.rounded(.down)))
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let totalEP = max(0, Int(totalDistanceKm.rounded(.down)))

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                    .frame(width: 68, height: 68)

                RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(.black)
                    .lineLimit(1)

                Text("Lv.1  ·  \(totalEP) EP")
                    .appCaptionStyle()
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(UITheme.accent)
                            .frame(width: max(8, proxy.size.width * 0.45), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(cityCount) \(localizedLabel(zh: "城市", en: "Cities"))  ·  \(totalJourneys) \(localizedLabel(zh: "旅程", en: "Trips"))  ·  \(totalMemories) \(localizedLabel(zh: "记忆", en: "Memories"))  ·  \(distanceKmDisplay)km")
                    .appFootnoteStyle()
                    .foregroundColor(.black.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                if let image = captureCurrentPageImage() {
                    shareItem = GlobeShareImageItem(image: image)
                }
            } label: {
                Label(localizedLabel(zh: "分享", en: "Share"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(UITheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private func localizedLabel(zh: String, en: String) -> String {
        if Locale.preferredLanguages.first?.hasPrefix("zh") == true {
            return zh
        }
        return en
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "EXPLORER" : value
    }

    private func captureCurrentPageImage() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
