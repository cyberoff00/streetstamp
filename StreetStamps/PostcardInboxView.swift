import SwiftUI
import UIKit

struct PostcardInboxView: View {
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

    @State private var selectedBox: Box
    @State private var pendingFocusMessageID: String?
    @State private var selectedDetail: PostcardDetailTarget?
    @State private var isRefreshing = false
    private let focusMessageID: String?

    init(initialBox: Box = .sent, focusMessageID: String? = nil) {
        _selectedBox = State(initialValue: initialBox)
        _pendingFocusMessageID = State(initialValue: focusMessageID)
        self.focusMessageID = focusMessageID
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
                VStack(spacing: 12) {
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
        .navigationTitle(L10n.t("postcard_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedDetail) { target in
            detailDestination(for: target)
        }
        .task {
            await refreshInbox()
            if focusMessageID != nil {
                selectedBox = .received
            }
            openFocusedMessageIfNeeded()
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
            openFocusedMessageIfNeeded()
        }
    }

    @ViewBuilder
    private var sentSection: some View {
        if postcardCenter.sentItems.isEmpty && pendingDrafts.isEmpty {
            emptyState(text: L10n.t("postcard_sent_empty"))
        } else {
            ForEach(postcardCenter.sentItems) { item in
                Button {
                    selectedDetail = PostcardDetailTarget(kind: .sent(messageID: item.messageID))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.cityName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(FigmaTheme.text)
                            Spacer()
                            Text(item.sentAt, style: .date)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FigmaTheme.subtext)
                        }

                        Text(item.messageText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)

                        Text("\(L10n.t("postcard_to_prefix"))\(item.toUserID)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }

            ForEach(pendingDrafts) { draft in
                Button {
                    selectedDetail = PostcardDetailTarget(kind: .draft(draftID: draft.draftID))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(draft.cityName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(FigmaTheme.text)
                            Spacer()
                            Text(draft.status.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(statusColor(draft.status))
                        }

                        Text(draft.message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)

                        Text("\(L10n.t("postcard_to_prefix"))\(draft.toUserID)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)

                        if draft.status == .failed {
                            Button {
                                Task {
                                    await postcardCenter.retry(
                                        draftID: draft.draftID,
                                        token: sessionStore.currentAccessToken,
                                        allowedCityIDs: [draft.cityID]
                                    )
                                }
                            } label: {
                                Text(L10n.t("postcard_retry"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(FigmaTheme.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        if postcardCenter.receivedItems.isEmpty {
            emptyState(text: L10n.t("postcard_received_empty"))
        } else {
            ForEach(postcardCenter.receivedItems) { item in
                Button {
                    selectedDetail = PostcardDetailTarget(kind: .received(messageID: item.messageID))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.cityName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(FigmaTheme.text)
                            Spacer()
                            Text(item.sentAt, style: .date)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FigmaTheme.subtext)
                        }

                        Text(item.messageText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)

                        Text("\(L10n.t("postcard_from_prefix"))\(item.fromDisplayName ?? item.fromUserID)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pendingDrafts: [PostcardDraft] {
        let sentIDs = Set(postcardCenter.sentItems.map(\.messageID))
        return postcardCenter.drafts.filter { draft in
            guard draft.status == .sent else { return true }
            guard let messageID = draft.messageID, !messageID.isEmpty else { return true }
            return !sentIDs.contains(messageID)
        }
    }

    @ViewBuilder
    private func detailDestination(for target: PostcardDetailTarget) -> some View {
        switch target.kind {
        case .draft(let draftID):
            if let draft = postcardCenter.drafts.first(where: { $0.draftID == draftID }) {
                PostcardDetailView(
                    cityName: draft.cityName,
                    messageText: draft.message,
                    nickname: draft.toUserID,
                    date: draft.sentAt ?? draft.updatedAt,
                    statusText: draft.status.rawValue.uppercased(),
                    localImagePath: draft.photoLocalPath,
                    remoteImageURL: nil
                )
            } else {
                emptyState(text: L10n.t("postcard_send_failed"))
            }
        case .sent(let messageID):
            if let item = postcardCenter.sentItems.first(where: { $0.messageID == messageID }) {
                PostcardDetailView(
                    cityName: item.cityName,
                    messageText: item.messageText,
                    nickname: item.toUserID,
                    date: item.sentAt,
                    statusText: (item.status ?? "sent").uppercased(),
                    localImagePath: nil,
                    remoteImageURL: item.photoURL
                )
            } else {
                emptyState(text: L10n.t("postcard_send_failed"))
            }
        case .received(let messageID):
            if let item = postcardCenter.receivedItems.first(where: { $0.messageID == messageID }) {
                PostcardDetailView(
                    cityName: item.cityName,
                    messageText: item.messageText,
                    nickname: item.fromDisplayName ?? item.fromUserID,
                    date: item.sentAt,
                    statusText: nil,
                    localImagePath: nil,
                    remoteImageURL: item.photoURL
                )
            } else {
                emptyState(text: L10n.t("postcard_send_failed"))
            }
        }
    }

    private func openFocusedMessageIfNeeded() {
        guard let messageID = pendingFocusMessageID, !messageID.isEmpty else { return }
        guard postcardCenter.receivedItems.contains(where: { $0.messageID == messageID }) else {
            Task {
                await refreshInbox()
                guard postcardCenter.receivedItems.contains(where: { $0.messageID == messageID }) else { return }
                selectedBox = .received
                selectedDetail = PostcardDetailTarget(kind: .received(messageID: messageID))
                pendingFocusMessageID = nil
            }
            return
        }
        selectedBox = .received
        selectedDetail = PostcardDetailTarget(kind: .received(messageID: messageID))
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
            Text("明信片同步异常：\(text)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("重试") {
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

    private func statusColor(_ status: PostcardDraftStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .sending: return .orange
        case .sent: return .green
        case .failed: return .red
        }
    }
}

private struct PostcardDetailTarget: Identifiable, Hashable {
    enum Kind: Hashable {
        case draft(draftID: String)
        case sent(messageID: String)
        case received(messageID: String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .draft(let draftID): return "draft_\(draftID)"
        case .sent(let messageID): return "sent_\(messageID)"
        case .received(let messageID): return "received_\(messageID)"
        }
    }
}

private struct PostcardDetailView: View {
    let cityName: String
    let messageText: String
    let nickname: String
    let date: Date
    let statusText: String?
    let localImagePath: String?
    let remoteImageURL: String?
    @State private var isFrontShowing = true
    @State private var saveToastText: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                FlippablePostcardView(
                    cityName: cityName,
                    nickname: nickname.uppercased(),
                    messageText: messageText,
                    photoSource: photoSource,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    isFront: $isFrontShowing,
                    onLongPress: {
                        saveCurrentFaceToPhotos()
                    }
                )

                HStack(spacing: 10) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                    Spacer(minLength: 8)
                    if let statusText, !statusText.isEmpty {
                        Text(statusText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(FigmaTheme.subtext)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let saveToastText {
                    Text(saveToastText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationTitle(cityName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photoSource: PostcardPhotoSource {
        if let localImagePath {
            let trimmed = localImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .localPath(trimmed)
            }
        }
        if let remoteImageURL {
            let trimmed = remoteImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .remoteURL(trimmed)
            }
        }
        return .none
    }

    private func saveCurrentFaceToPhotos() {
        guard #available(iOS 16.0, *), let image = renderFaceImage(isFront: isFrontShowing) else {
            saveToastText = "保存失败"
            clearSaveToastSoon()
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saveToastText = isFrontShowing ? "已保存明信片正面" : "已保存明信片反面"
        clearSaveToastSoon()
    }

    @available(iOS 16.0, *)
    private func renderFaceImage(isFront: Bool) -> UIImage? {
        let width: CGFloat = 1080
        let height: CGFloat = width / (3.0 / 2.0)

        let faceView: AnyView
        if isFront {
            faceView = AnyView(
                PostcardFrontFaceView(
                    cityName: cityName,
                    nickname: nickname.uppercased(),
                    photoSource: photoSource,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    cornerRadius: 22
                )
            )
        } else {
            faceView = AnyView(
                PostcardBackFaceView(
                    cityName: cityName,
                    nickname: nickname.uppercased(),
                    messageText: messageText,
                    avatarLoadout: AvatarLoadoutStore.load(),
                    cornerRadius: 22
                )
            )
        }

        let renderView = faceView
            .frame(width: width, height: height)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func clearSaveToastSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saveToastText = nil
        }
    }
}
