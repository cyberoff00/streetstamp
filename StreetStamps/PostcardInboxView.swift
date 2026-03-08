import SwiftUI
import UIKit

struct PostcardInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    enum Box: String, CaseIterable, Identifiable {
        case sent = "sent"
        case received = "received"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .sent: return L10n.t("postcard_box_sent")
            case .received: return L10n.t("postcard_box_received")
            }
        }
    }

    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var postcardCenter: PostcardCenter
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var selectedBox: Box
    @State private var pendingFocusMessageID: String?
    @State private var isRefreshing = false
    private let focusMessageID: String?

    init(initialBox: Box = .sent, focusMessageID: String? = nil) {
        _selectedBox = State(initialValue: initialBox)
        _pendingFocusMessageID = State(initialValue: focusMessageID)
        self.focusMessageID = focusMessageID
    }

    private var myDisplayName: String {
        let normalized = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "EXPLORER" : normalized
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Postcards", selection: $selectedBox) {
                ForEach(Box.allCases) { box in
                    Text(box.title).tag(box)
                }
            }
            .pickerStyle(.segmented)

            if let syncError = postcardCenter.lastSyncError, !syncError.isEmpty {
                syncErrorBanner(syncError)
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    if selectedBox == .sent {
                        sentSection
                    } else {
                        receivedSection
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(FigmaTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: L10n.t("postcard_nav_title"),
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 16,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await refreshInbox()
            if focusMessageID != nil {
                selectedBox = .received
            }
            autoFocusReceivedIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshInbox()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
                await refreshInbox()
            }
        }
        .refreshable {
            await refreshInbox()
        }
        .onReceive(postcardCenter.$receivedItems) { _ in
            autoFocusReceivedIfNeeded()
        }
    }

    // MARK: - Sent

    @ViewBuilder
    private var sentSection: some View {
        let visibleDrafts = pendingDrafts.filter { $0.status != .failed }
        if postcardCenter.sentItems.isEmpty && visibleDrafts.isEmpty {
            emptyState(text: L10n.t("postcard_sent_empty"))
        } else {
            ForEach(postcardCenter.sentItems) { item in
                PostcardCardRow(
                    cityName: item.cityName,
                    nickname: myDisplayName.uppercased(),
                    messageText: item.messageText,
                    photoSource: photoSource(for: item),
                    sentDate: item.sentAt,
                    metaLabel: "\(L10n.t("postcard_to_prefix"))\(item.toDisplayName ?? item.toUserID)"
                )
            }

            ForEach(visibleDrafts) { draft in
                PostcardCardRow(
                    cityName: draft.cityName,
                    nickname: myDisplayName.uppercased(),
                    messageText: draft.message,
                    photoSource: draftPhotoSource(draft),
                    sentDate: draft.sentAt ?? draft.updatedAt,
                    metaLabel: "\(L10n.t("postcard_to_prefix"))\(draft.toUserID)",
                    statusBadge: draft.status == .sending ? L10n.t("postcard_sending") : nil
                )
            }
        }
    }

    // MARK: - Received

    @ViewBuilder
    private var receivedSection: some View {
        if postcardCenter.receivedItems.isEmpty {
            emptyState(text: L10n.t("postcard_received_empty"))
        } else {
            ForEach(postcardCenter.receivedItems) { item in
                PostcardCardRow(
                    cityName: item.cityName,
                    nickname: (item.fromDisplayName ?? item.fromUserID).uppercased(),
                    messageText: item.messageText,
                    photoSource: photoSource(for: item),
                    sentDate: item.sentAt,
                    metaLabel: "\(L10n.t("postcard_from_prefix"))\(item.fromDisplayName ?? item.fromUserID)"
                )
            }
        }
    }

    // MARK: - Helpers

    private var pendingDrafts: [PostcardDraft] {
        let sentIDs = Set(postcardCenter.sentItems.map(\.messageID))
        return postcardCenter.drafts.filter { draft in
            guard draft.status == .sent else { return true }
            guard let messageID = draft.messageID, !messageID.isEmpty else { return true }
            return !sentIDs.contains(messageID)
        }
    }

    private func photoSource(for item: BackendPostcardMessageDTO) -> PostcardPhotoSource {
        if let url = item.photoURL, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .remoteURL(url)
        }
        return .none
    }

    private func draftPhotoSource(_ draft: PostcardDraft) -> PostcardPhotoSource {
        let path = draft.photoLocalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .none }
        if path.lowercased().hasPrefix("http") {
            return .remoteURL(path)
        }
        return .localPath(path)
    }

    private func autoFocusReceivedIfNeeded() {
        guard let messageID = pendingFocusMessageID, !messageID.isEmpty else { return }
        guard postcardCenter.receivedItems.contains(where: { $0.messageID == messageID }) else {
            Task {
                await refreshInbox()
                guard postcardCenter.receivedItems.contains(where: { $0.messageID == messageID }) else { return }
                selectedBox = .received
                pendingFocusMessageID = nil
            }
            return
        }
        selectedBox = .received
        pendingFocusMessageID = nil
    }

    private func refreshInbox() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await postcardCenter.refreshFromBackend(token: sessionStore.currentAccessToken)
    }

    private func syncErrorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
            Text(String(format: L10n.t("postcard_sync_error_format"), text))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(L10n.t("retry")) {
                Task { await refreshInbox() }
            }
            .font(.system(size: 12, weight: .bold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(FigmaTheme.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}

// MARK: - Card Row (each card has its own flip state)

private struct PostcardCardRow: View {
    let cityName: String
    let nickname: String
    let messageText: String
    let photoSource: PostcardPhotoSource
    let sentDate: Date
    let metaLabel: String
    var statusBadge: String? = nil

    @State private var isFront = true
    @State private var saveToastText: String?

    var body: some View {
        VStack(spacing: 10) {
            FlippablePostcardView(
                cityName: cityName,
                nickname: nickname,
                messageText: messageText,
                photoSource: photoSource,
                avatarLoadout: AvatarLoadoutStore.load(),
                isFront: $isFront,
                sentDate: sentDate,
                onLongPress: { saveCurrentFaceToPhotos() }
            )

            HStack(spacing: 8) {
                Text(metaLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let statusBadge {
                    Text(statusBadge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text(sentDate, style: .date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.horizontal, 4)

            if let saveToastText {
                Text(saveToastText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
    }

    private func saveCurrentFaceToPhotos() {
        guard #available(iOS 16.0, *), let image = renderFaceImage(isFront: isFront) else {
            saveToastText = "保存失败"
            clearSaveToastSoon()
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saveToastText = isFront ? "已保存明信片正面" : "已保存明信片反面"
        clearSaveToastSoon()
    }

    @available(iOS 16.0, *)
    private func renderFaceImage(isFront: Bool) -> UIImage? {
        let width: CGFloat = 540
        let height: CGFloat = width / (3.0 / 2.0)

        let faceView: AnyView
        if isFront {
            faceView = AnyView(
                PostcardFrontFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    photoSource: photoSource,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    cornerRadius: 22
                )
            )
        } else {
            faceView = AnyView(
                PostcardBackFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    messageText: messageText,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    sentDate: sentDate,
                    cornerRadius: 22
                )
            )
        }

        let renderView = faceView
            .frame(width: width, height: height)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func clearSaveToastSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saveToastText = nil
        }
    }
}
