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
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var faceIndex: Int = 0
    @State private var dragAccum: CGFloat = 0

    @State private var loadout: RobotLoadout
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var nameError = ""
    @State private var isSavingName = false
    @State private var toastText = ""
    @State private var showToast = false
    @State private var socialNotifications: [BackendNotificationItem] = []
    @State private var unreadSocialCount = 0
    @State private var showNotificationsSheet = false
    @State private var notificationsLoading = false

    init() {
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

    private var totalMemories: Int {
        store.journeys.reduce(0) { $0 + $1.memories.count }
    }

    private var levelValue: Int {
        max(1, Int((totalDistance / 50.0).rounded(.down)) + 1)
    }

    private var epValue: Int {
        max(0, Int((totalDistance * 100.0).rounded()))
    }

    private var displayName: String {
        let value = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private var likeNotificationCount: Int {
        socialNotifications.filter { $0.type == "journey_like" }.count
    }

    private var stompNotificationCount: Int {
        socialNotifications.filter { $0.type == "profile_stomp" }.count
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
                            topActionRow
                        }
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 56)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onChange(of: loadout) { _, newValue in
            AvatarLoadoutStore.save(newValue)
        }
        .sheet(isPresented: $showNameEditor) {
            profileNameEditorSheet
        }
        .sheet(isPresented: $showNotificationsSheet) {
            socialNotificationsSheet
        }
        .task {
            await refreshDisplayNameIfNeeded()
            await refreshSocialNotifications(showToastForLatestUnread: true)
        }
        .onChange(of: sessionStore.currentAccessToken) { _, _ in
            Task {
                await refreshSocialNotifications(showToastForLatestUnread: false)
            }
        }
    }
    
    // MARK: - Header View
    
    // MARK: - Updated Profile Header to match UI script

    private var headerView: some View {
        HStack {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text(L10n.t("profile_title"))
                .appHeaderStyle()
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
                .overlay(alignment: .topTrailing) {
                    NavigationLink {
                        EquipmentView(loadout: $loadout)
                    } label: {
                        Image(systemName: "tshirt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.primary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.95))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -8)
                }
            }
            .padding(.top, 32)

            Button {
                nameDraft = displayName == L10n.t("explorer_fallback") ? "" : displayName
                nameError = ""
                showNameEditor = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.4)
                        .foregroundColor(FigmaTheme.text)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 24)

            HStack(spacing: 8) {
                Text(String(format: L10n.t("level_format"), levelValue))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.62))
                Text("·")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.text.opacity(0.42))
                Text(String(format: L10n.t("ep_format"), epValue.formatted()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.72))
            }
            .padding(.top, 6)

            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
                .padding(.top, 22)

            HStack(spacing: 0) {
                embeddedStatItem(icon: "mappin.and.ellipse", value: "\(totalJourneys)", label: "TRIPS")
                Rectangle()
                    .fill(FigmaTheme.border)
                    .frame(width: 1, height: 52)
                embeddedStatItem(icon: "heart", value: "\(totalMemories)", label: "MEMORIES")
                Rectangle()
                    .fill(FigmaTheme.border)
                    .frame(width: 1, height: 52)
                embeddedStatItem(icon: "paperplane", value: "\(citiesVisited)", label: "CITIES")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .figmaAvatarCardStyle()
    }

    private var topActionRow: some View {
        VStack(spacing: 14) {
            Button {
                showNotificationsSheet = true
                Task {
                    await markSocialNotificationsReadIfNeeded()
                }
            } label: {
                socialNotificationTile
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(FigmaTheme.text)
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

    private func embeddedStatItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(0.1)
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(FigmaTheme.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    private var socialNotificationTile: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.96, blue: 1.0))
                    .frame(width: 56, height: 56)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(red: 0.22, green: 0.45, blue: 0.89))

                if unreadSocialCount > 0 {
                    Text("\(min(unreadSocialCount, 99))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 11, y: -9)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("互动通知")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                Text("收到赞 \(likeNotificationCount) · 被踩 \(stompNotificationCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
                if unreadSocialCount > 0 {
                    Text("未读 \(unreadSocialCount) 条")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.45, blue: 0.89))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .profileFeatureCardStyle()
    }

    @ViewBuilder
    private var socialNotificationsSheet: some View {
        NavigationStack {
            Group {
                if notificationsLoading && socialNotifications.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载通知中...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if socialNotifications.isEmpty {
                    Text("暂时还没有互动通知")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(socialNotifications) { item in
                                socialNotificationRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(FigmaTheme.background.ignoresSafeArea())
            .navigationTitle("互动通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        showNotificationsSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        Task {
                            await refreshSocialNotifications(showToastForLatestUnread: false)
                        }
                    }
                }
            }
            .task {
                await refreshSocialNotifications(showToastForLatestUnread: false)
            }
        }
    }

    private func socialNotificationRow(_ item: BackendNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.read ? Color.clear : Color(red: 0.22, green: 0.45, blue: 0.89))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.type == "journey_like" ? "收到点赞" : "主页被踩")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(item.type == "journey_like" ? Color.red : Color(red: 0.22, green: 0.45, blue: 0.89))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())

                    Text(relativeTimeText(item.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }

                Text(item.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
    }

    private func rotateLeft() {
        faceIndex = (faceIndex - 1 + RobotFace.allCases.count) % RobotFace.allCases.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rotateRight() {
        faceIndex = (faceIndex + 1) % RobotFace.allCases.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private var profileNameEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("可修改昵称（1-24 字符）")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                TextField("输入昵称", text: $nameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .semibold))

                Text("支持多语言字母、数字和 . _ -，不能包含空格")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                if !nameError.isEmpty {
                    Text(nameError)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        showNameEditor = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSavingName ? "保存中..." : "保存") {
                        Task {
                            await saveDisplayName()
                        }
                    }
                    .disabled(isSavingName)
                }
            }
        }
    }

    private func validateDisplayName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "昵称不能为空" }
        guard trimmed.count <= 24 else { return "昵称最多 24 个字符" }
        guard !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
            return "昵称不能包含空格"
        }
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "._-"))
        let valid = trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        return valid ? nil : "昵称仅支持字母、数字和 . _ -"
    }

    @MainActor
    private func saveDisplayName() async {
        if let error = validateDisplayName(nameDraft) {
            nameError = error
            return
        }
        nameError = ""
        isSavingName = true
        defer { isSavingName = false }

        let normalized = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        profileName = normalized

        if BackendConfig.isEnabled,
           let token = sessionStore.currentAccessToken,
           !token.isEmpty {
            do {
                let profile = try await BackendAPIClient.shared.updateDisplayName(
                    token: token,
                    displayName: normalized
                )
                profileName = profile.displayName
            } catch {
                showToastMessage("昵称已本地更新，云端保存失败：\(error.localizedDescription)")
            }
        }

        showNameEditor = false
        showToastMessage("昵称已更新")
    }

    @MainActor
    private func refreshDisplayNameIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            if !me.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileName = me.displayName
            }
        } catch {
            // Keep profile editable even if backend request fails.
        }
    }

    @MainActor
    private func refreshSocialNotifications(showToastForLatestUnread: Bool) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            socialNotifications = []
            unreadSocialCount = 0
            return
        }
        notificationsLoading = true
        defer { notificationsLoading = false }

        do {
            let all = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: false)
            let supportedTypes: Set<String> = ["journey_like", "profile_stomp"]
            let socialItems = all
                .filter { supportedTypes.contains($0.type) }
                .sorted(by: { $0.createdAt > $1.createdAt })
            socialNotifications = socialItems

            let unread = socialItems.filter { !$0.read }
            unreadSocialCount = unread.count

            if showToastForLatestUnread,
               let latest = unread.first {
                showToastMessage(latest.message)
            }
        } catch {
            // Keep profile view responsive even if notification poll fails.
        }
    }

    @MainActor
    private func markSocialNotificationsReadIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        let unreadIDs = socialNotifications
            .filter { !$0.read }
            .map(\.id)
        guard !unreadIDs.isEmpty else { return }

        do {
            try await BackendAPIClient.shared.markNotificationsRead(token: token, ids: unreadIDs)
            socialNotifications = socialNotifications.map { item in
                guard unreadIDs.contains(item.id) else { return item }
                var copy = item
                copy.read = true
                return copy
            }
            unreadSocialCount = 0
        } catch {
            // Keep sheet usable even if mark-read fails.
        }
    }

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @MainActor
    private func showToastMessage(_ text: String) {
        toastText = text
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
}

private extension View {
    func figmaAvatarCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
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
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(FigmaTheme.text)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.4))
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
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(FigmaTheme.text)

            }

            Spacer()

//            Text(value)
//                .font(.system(size: 16, weight: .bold))
//                .foregroundColor(FigmaTheme.text)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.35))
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
                .foregroundColor(FigmaTheme.text.opacity(0.5))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(FigmaTheme.text)
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
                .foregroundColor(FigmaTheme.text.opacity(0.5))

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.35))
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
                        .foregroundColor(FigmaTheme.text.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("recent_journeys_title"))
                    .appHeaderStyle()
                    .foregroundColor(FigmaTheme.text)

                Text(String(format: L10n.t("recent_journeys_last_30_days"), locale: Locale.current, recentJourneys.count))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(FigmaTheme.text.opacity(0.5))
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
                .foregroundColor(FigmaTheme.text.opacity(0.6))

            Text(L10n.key("recent_journeys_empty_desc"))
                .font(.system(size: 12))
                .foregroundColor(FigmaTheme.text.opacity(0.45))
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
            return L10n.t("unknown_country")
        }
        return Locale.current.localizedString(forRegionCode: iso) ?? iso
    }

    private var detailButtonText: String {
        L10n.t("view_journey_memories")
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
                                    .foregroundColor(FigmaTheme.text.opacity(0.45))
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
                        .foregroundColor(FigmaTheme.text.opacity(0.75))
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
                    .foregroundColor(FigmaTheme.text)

                Text(dateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.5))

                HStack(spacing: 10) {
                    Text(String(format: "%.2f km", max(0, journey.distance / 1000.0)))
                    Text("·")
                    Text(durationText)
                    Text("·")
                    Text(String(format: L10n.t("mem_short"), locale: Locale.current, journey.memories.count))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FigmaTheme.text.opacity(0.45))
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
                .foregroundColor(FigmaTheme.text.opacity(0.78))
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
                self.saveToastText = (err == nil) ? L10n.t("share_saved_to_photos") : L10n.t("save_failed")
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
                // Header
                ZStack {
                    Text(L10n.t("equipment_title_upper"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(1)
                        .foregroundColor(FigmaTheme.text)

                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(FigmaTheme.text.opacity(0.6))
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Text(String(format: L10n.t("equipment_collected_count"), locale: Locale.current, collectedCount, equipmentItems.count))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(FigmaTheme.text.opacity(0.5))
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                
                // Equipment grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(equipmentItems) { item in
                            EquipmentCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 360)
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
        VStack(spacing: 6) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isCollected ? Color.white : Color.black.opacity(0.05))
                    .frame(height: 62)
                
                if item.isCollected {
                    Image(systemName: item.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.7))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.3))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.isCollected ? Color.black.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            
            // Name and rarity
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(item.isCollected ? .black : .black.opacity(0.4))
                    .lineLimit(1)
                
                Text(item.rarity.label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(item.isCollected ? item.rarity.color : .black.opacity(0.3))
            }
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.rarity == .rare && item.isCollected ? UITheme.accent.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
