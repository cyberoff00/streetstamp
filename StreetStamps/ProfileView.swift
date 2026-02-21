//
//  ProfileView.swift
//  StreetStamps
//
//  Created by Claire Yang on 18/01/2026.
//

import Foundation
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    
    @Binding var showSidebar: Bool
    @State private var faceIndex: Int = 0
    @State private var dragAccum: CGFloat = 0

    @State private var loadout: RobotLoadout

    init(showSidebar: Binding<Bool>) {
        self._showSidebar = showSidebar
        self._loadout = State(initialValue: AvatarLoadoutStore.load())
    }

    
    // Computed stats
    private var totalJourneys: Int {
        store.journeys.count
    }
    
    private var totalDistance: Double {
        let meters = store.journeys.reduce(into: 0.0) { total, journey in
            total += journey.distance
        }
        return meters / 1000.0 // km
    }
    
    private var citiesVisited: Int {
        cityCache.cachedCities.count
    }

    private var levelValue: Int {
        max(1, Int((totalDistance / 50.0).rounded(.down)) + 1)
    }

    private var epValue: Int {
        max(0, Int((totalDistance * 100.0).rounded()))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FigmaTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerView
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            avatarHeaderCard
                            bottomStatsRow
                            topActionRow
                        }
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: loadout) { _, newValue in
            AvatarLoadoutStore.save(newValue)
        }
    }
    
    // MARK: - Header View
    
    // MARK: - Updated Profile Header to match UI script

    private var headerView: some View {
        HStack {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            Spacer()

            Text("PROFILE")
                .appHeaderStyle()
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }

    private var avatarHeaderCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(FigmaTheme.primary.opacity(0.17))
                    .blur(radius: 20)
                    .frame(width: 132, height: 132)

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FigmaTheme.primary.opacity(0.10),
                                FigmaTheme.accent.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                    .shadow(color: FigmaTheme.primary.opacity(0.12), radius: 24, x: 0, y: 4)

                RobotRendererView(
                    size: 96,
                    face: RobotFace.allCases[faceIndex],
                    loadout: loadout
                )
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let delta = value.translation.width - dragAccum
                        dragAccum = value.translation.width
                        if delta > 12 {
                            rotateLeft()
                        } else if delta < -12 {
                            rotateRight()
                        }
                    }
                    .onEnded { _ in
                        dragAccum = 0
                    }
                )
            }
            .padding(.top, 32)

            HStack(spacing: 6) {
                Text("MYDEARFRIENDK")
                    .font(.system(size: 20, weight: .black))
                    .tracking(-0.4)
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.45))
            }
            .padding(.top, 24)

            Text("EXPLORER")
                .font(.system(size: 13, weight: .regular))
                .tracking(0.2)
                .foregroundColor(FigmaTheme.subtext)
                .padding(.top, 6)

            HStack(spacing: 8) {
                Text("Lv.\(levelValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.62))
                Text("·")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.42))
                Text("\(epValue.formatted()) EP")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.72))
            }
            .padding(.top, 6)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .figmaAvatarCardStyle()
    }

    private var topActionRow: some View {
        HStack(spacing: 14) {
            NavigationLink {
                EquipmentView(loadout: $loadout)
            } label: {
                profileMenuTile(
                    icon: "tshirt",
                    iconColor: FigmaTheme.primary,
                    iconBg: FigmaTheme.primary.opacity(0.14),
                    title: "EQUIPMENT"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MyJourneysView()
            } label: {
                profileMenuTile(
                    icon: "map",
                    iconColor: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255),
                    iconBg: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255).opacity(0.14),
                    title: "MY JOURNEY"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomStatsRow: some View {
        HStack(spacing: 14) {
            profileStatTile(icon: "mappin.and.ellipse", value: "\(totalJourneys)", label: "TRIPS")
            profileStatTile(icon: "arrow.up.right", value: "\(Int(totalDistance.rounded()))km", label: "DISTANCE")
            profileStatTile(icon: "paperplane", value: "\(citiesVisited)", label: "CITIES")
        }
    }

    private func profileMenuTile(icon: String, iconColor: Color, iconBg: Color, title: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .tracking(-0.3)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .padding(.vertical, 8)
        .profileFeatureCardStyle()
    }

    private func profileStatTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(FigmaTheme.subtext)
                .padding(.top, 2)

            Text(value)
                .font(.system(size: 18, weight: .black))
                .tracking(0.1)
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(FigmaTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 115)
        .profileStatCardStyle()
    }

    private func rotateLeft() {
        faceIndex = (faceIndex - 1 + RobotFace.allCases.count) % RobotFace.allCases.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rotateRight() {
        faceIndex = (faceIndex + 1) % RobotFace.allCases.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private extension View {
    func figmaAvatarCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }

    func profileStatCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)
    }

    func profileFeatureCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }

}

// MARK: - Profile Action Button

struct ProfileActionButton: View {
    let icon: String
    let title: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(FigmaTheme.primary)
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(FigmaTheme.mutedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Section Link Row (non-expandable)

struct SectionLinkRow: View {
    let title: String
//    let subtitle: String
  //  let value: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.black)

            }

            Spacer()

//            Text(value)
//                .font(.system(size: 16, weight: .bold))
//                .foregroundColor(.black)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.35))
                .padding(.leading, 2)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.accent)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.5))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Stat Navigation Row

struct StatNavRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.accent)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.5))

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.35))
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Recent Journeys

struct RecentJourneysView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    private var cutoffDate: Date {
        // "过去一个月"：这里按最近 30 天计算
        Date().addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private var recentJourneys: [JourneyRoute] {
        store.journeys
            .filter { j in
                guard let start = j.startTime, let end = j.endTime else { return false }
                guard end >= cutoffDate else { return false }
                guard !j.isTooShort else { return false }
                return end >= start
            }
            .sorted { (a, b) in
                (a.endTime ?? .distantPast) > (b.endTime ?? .distantPast)
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            UITheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if recentJourneys.isEmpty {
                            emptyState
                        } else {
                            ForEach(recentJourneys, id: \.id) { j in
                                RecentJourneyCard(journey: j)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT JOURNEYS")
                    .appHeaderStyle()
                    .foregroundColor(.black)

                Text(String(format: L10n.t("recent_journeys_last_30_days"), locale: Locale.current, recentJourneys.count))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(.black.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 10)
        }
        .background(UITheme.bg)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(L10n.key("recent_journeys_empty_title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.6))

            Text(L10n.key("recent_journeys_empty_desc"))
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 18)
    }
}

struct RecentJourneyCard: View {
    var journey: JourneyRoute

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @State private var image: UIImage? = nil
    @State private var isGenerating = false
    @State private var showSaveToast = false
    @State private var saveToastText = L10n.t("share_saved_to_photos")
    @State private var imageSaver: ImageSaver? = nil

    private var durationText: String {
        guard let start = journey.startTime else {
            return String(format: L10n.t("share_duration_min"), locale: Locale.current, 0)
        }
        let end = journey.endTime ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return String(format: L10n.t("share_duration_min"), locale: Locale.current, minutes)
    }

    private var dateText: String {
        guard let end = journey.endTime else { return "" }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: end)
    }

    private var localizedCountryName: String {
        let iso = (journey.countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard iso.count == 2 else {
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "未知国家" : "Unknown Country"
        }
        return Locale.current.localizedString(forRegionCode: iso) ?? iso
    }

    private var detailButtonText: String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "查看旅程记忆" : "View Journey Memories"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            saveToPhotos(img)
                        }
                        .contextMenu {
                            Button {
                                saveToPhotos(img)
                            } label: {
                                Label(L10n.t("save_image"), systemImage: "square.and.arrow.down")
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 320)
                        .overlay(
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(L10n.key("share_generating"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                if showSaveToast {
                    Text(saveToastText)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(.black.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(journey.displayCityName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                Text(dateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.5))

                HStack(spacing: 10) {
                    Text(String(format: "%.2f km", max(0, journey.distance / 1000.0)))
                    Text("·")
                    Text(durationText)
                    Text("·")
                    Text(String(format: L10n.t("mem_short"), locale: Locale.current, journey.memories.count))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black.opacity(0.45))
            }
            .padding(.horizontal, 2)

            NavigationLink {
                DeferredView {
                    JourneyMemoryDetailView(
                        journey: journey,
                        memories: journey.memories.sorted(by: { $0.timestamp < $1.timestamp }),
                        cityName: journey.displayCityName,
                        countryName: localizedCountryName
                    )
                    .environmentObject(store)
                    .environmentObject(sessionStore)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 12, weight: .semibold))
                    Text(detailButtonText)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.black.opacity(0.78))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            generateIfNeeded()
        }
    }

    private func generateIfNeeded() {
        guard image == nil, !isGenerating else { return }

        // too short / empty journey -> show placeholder card
        if journey.coordinates.count < 1 || journey.isTooShort {
            image = ShareCardGenerator.placeholderCard()
            return
        }

        isGenerating = true
        ShareCardGenerator.generate(journey: journey, privacy: .exact) { img in
            self.image = img
            self.isGenerating = false
        }
    }

    private func saveToPhotos(_ img: UIImage) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Hold a strong reference until completion callback
        let saver = ImageSaver { err in
            DispatchQueue.main.async {
                self.imageSaver = nil
                self.saveToastText = (err == nil) ? "Saved to Photos" : "Failed to Save"
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.showSaveToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showSaveToast = false
                    }
                }
            }
        }
        self.imageSaver = saver
        saver.writeToPhotoAlbum(img)
    }
}

private struct DeferredView<Content: View>: View {
    let content: () -> Content
    var body: some View { content() }
}

final class ImageSaver: NSObject {
    private let onComplete: (Error?) -> Void

    init(onComplete: @escaping (Error?) -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func writeToPhotoAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        onComplete(error)
    }
}

// MARK: - Equipment Library View (Updated)

struct EquipmentLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    
    let equipmentItems: [EquipmentItem] = [
        EquipmentItem(id: "worldmap", name: L10n.t("equipment_world_map"), icon: "map", rarity: .common, isCollected: true),
        EquipmentItem(id: "camera", name: L10n.t("equipment_camera"), icon: "camera", rarity: .common, isCollected: true),
        EquipmentItem(id: "backpack", name: L10n.t("equipment_leather_backpack"), icon: "backpack", rarity: .rare, isCollected: false),
        EquipmentItem(id: "boots", name: L10n.t("equipment_hiking_boots"), icon: "figure.walk", rarity: .rare, isCollected: false)
    ]
    
    var collectedCount: Int {
        equipmentItems.filter { $0.isCollected }.count
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            UITheme.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back button and title
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("EQUIPMENT")
                        .font(.system(size: 26, weight: .black))
                        .tracking(1)
                        .foregroundColor(.black)
                    
                    Text(String(format: L10n.t("equipment_collected_count"), locale: Locale.current, collectedCount, equipmentItems.count))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .foregroundColor(.black.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Equipment grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(equipmentItems) { item in
                            EquipmentCard(item: item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Equipment Item Model

struct EquipmentItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let rarity: EquipmentRarity
    let isCollected: Bool
}

enum EquipmentRarity {
    case common
    case rare
    
    var label: String {
        switch self {
        case .common: return L10n.t("rarity_common")
        case .rare: return L10n.t("rarity_rare")
        }
    }
    
    var color: Color {
        switch self {
        case .common: return UITheme.rarityCommon
        case .rare: return UITheme.rarityRare
        }
    }
}

// MARK: - Equipment Card

struct EquipmentCard: View {
    let item: EquipmentItem
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isCollected ? Color.white : Color.black.opacity(0.05))
                    .frame(height: 80)
                
                if item.isCollected {
                    Image(systemName: item.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.black.opacity(0.7))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black.opacity(0.3))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.isCollected ? Color.black.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            
            // Name and rarity
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .foregroundColor(item.isCollected ? .black : .black.opacity(0.4))
                    .lineLimit(1)
                
                Text(item.rarity.label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(item.isCollected ? item.rarity.color : .black.opacity(0.3))
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(item.rarity == .rare && item.isCollected ? UITheme.accent.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
