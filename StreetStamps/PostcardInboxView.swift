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
    @EnvironmentObject private var socialStore: SocialGraphStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var selectedBox: Box
    @State private var pendingFocusMessageID: String?
    @State private var isRefreshing = false
    @State private var showComposer = false
    private let focusMessageID: String?
    private let friendID: String?
    private let friendName: String?

    init(initialBox: Box = .sent, focusMessageID: String? = nil, friendID: String? = nil, friendName: String? = nil) {
        _selectedBox = State(initialValue: initialBox)
        _pendingFocusMessageID = State(initialValue: focusMessageID)
        self.focusMessageID = focusMessageID
        self.friendID = friendID
        self.friendName = friendName
    }

    static func viewIdentity(initialBox: Box, focusMessageID: String?) -> String {
        PostcardInboxPresentation.viewIdentity(initialBox: initialBox, focusMessageID: focusMessageID)
    }

    private var myDisplayName: String {
        let normalized = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "EXPLORER" : normalized
    }

    private var myLoadout: RobotLoadout {
        AvatarLoadoutStore.load().normalizedForCurrentAvatar()
    }

    private var friendLoadoutsByUserID: [String: RobotLoadout] {
        Dictionary(
            uniqueKeysWithValues: socialStore.friends.map { friend in
                (friend.id, friend.loadout.normalizedForCurrentAvatar())
            }
        )
    }

    private var filteredSentItems: [BackendPostcardMessageDTO] {
        guard let friendID else { return postcardCenter.sentItems }
        return postcardCenter.sentItems.filter { $0.toUserID == friendID }
    }

    private var filteredReceivedItems: [BackendPostcardMessageDTO] {
        guard let friendID else { return postcardCenter.receivedItems }
        return postcardCenter.receivedItems.filter { $0.fromUserID == friendID }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker(L10n.t("postcard_picker_title"), selection: $selectedBox) {
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
                    title: L10n.upper("postcard_nav_title"),
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 16,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                if selectedBox == .sent {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "envelope")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("postcard_new_accessibility_label"))
                } else {
                    Color.clear
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .navigationDestination(isPresented: $showComposer) {
            if let friendID, let friendName {
                PostcardComposerView(friendID: friendID, friendName: friendName)
            } else {
                PostcardComposerView()
            }
        }
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
        if filteredSentItems.isEmpty && filteredPendingDrafts.isEmpty {
            emptyState(text: L10n.t("postcard_sent_empty"))
        } else {
            ForEach(filteredSentItems) { item in
                let recipientLabel = PostcardInboxPresentation.recipientLabel(
                    toDisplayName: item.toDisplayName,
                    toUserID: item.toUserID,
                    fallbackDisplayName: fallbackDisplayName(for: item.toUserID)
                )
                PostcardCardRow(
                    cityName: displayCityName(for: item),
                    nickname: myDisplayName.uppercased(),
                    messageText: item.messageText,
                    photoSource: photoSource(for: item),
                    photoURL: item.photoURL,
                    avatarLoadout: PostcardInboxPresentation.avatarLoadout(
                        for: item,
                        box: .sent,
                        myUserID: sessionStore.currentUserID,
                        myLoadout: myLoadout,
                        friendLoadoutsByUserID: friendLoadoutsByUserID
                    ),
                    sentDate: item.sentAt,
                    metaLabel: "\(L10n.t("postcard_to_prefix"))\(recipientLabel)",
                    reaction: PostcardInboxPresentation.cardReaction(for: item, box: .sent)
                )
            }

            ForEach(filteredPendingDrafts) { draft in
                let recipientLabel = PostcardInboxPresentation.recipientLabel(
                    toDisplayName: draft.toDisplayName,
                    toUserID: draft.toUserID,
                    fallbackDisplayName: fallbackDisplayName(for: draft.toUserID)
                )
                let statusPresentation = PostcardInboxPresentation.draftStatusPresentation(for: draft.status)
                PostcardCardRow(
                    cityName: displayCityName(for: draft),
                    nickname: myDisplayName.uppercased(),
                    messageText: draft.message,
                    photoSource: draftPhotoSource(draft),
                    photoURL: nil,
                    avatarLoadout: myLoadout,
                    sentDate: draft.sentAt ?? draft.updatedAt,
                    metaLabel: "\(L10n.t("postcard_to_prefix"))\(recipientLabel)",
                    statusBadge: statusPresentation?.badgeText,
                    statusDetail: statusPresentation?.detailText,
                    statusTone: statusTone(for: draft.status),
                    retryTitle: statusPresentation?.showsRetry == true ? L10n.t("postcard_retry") : nil,
                    onRetry: statusPresentation?.showsRetry == true ? {
                        Task {
                            await postcardCenter.retry(
                                draftID: draft.draftID,
                                token: sessionStore.currentAccessToken
                            )
                        }
                    } : nil
                )
            }
        }
    }

    // MARK: - Received

    @ViewBuilder
    private var receivedSection: some View {
        if filteredReceivedItems.isEmpty {
            emptyState(text: L10n.t("postcard_received_empty"))
        } else {
            ForEach(filteredReceivedItems) { item in
                let senderLabel = PostcardInboxPresentation.senderLabel(
                    fromDisplayName: item.fromDisplayName,
                    fromUserID: item.fromUserID,
                    fallbackDisplayName: fallbackDisplayName(for: item.fromUserID)
                )
                PostcardCardRow(
                    cityName: displayCityName(for: item),
                    nickname: senderLabel.uppercased(),
                    messageText: item.messageText,
                    photoSource: photoSource(for: item),
                    photoURL: item.photoURL,
                    avatarLoadout: PostcardInboxPresentation.avatarLoadout(
                        for: item,
                        box: .received,
                        myUserID: sessionStore.currentUserID,
                        myLoadout: myLoadout,
                        friendLoadoutsByUserID: friendLoadoutsByUserID
                    ),
                    sentDate: item.sentAt,
                    metaLabel: "\(L10n.t("postcard_from_prefix"))\(senderLabel)",
                    messageID: item.messageID,
                    token: sessionStore.currentAccessToken,
                    reaction: PostcardInboxPresentation.cardReaction(for: item, box: .received)
                )
                .onAppear {
                    Task {
                        guard let token = sessionStore.currentAccessToken else { return }
                        try? await BackendAPIClient.shared.markPostcardViewed(
                            token: token,
                            messageID: item.messageID
                        )
                    }
                }
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

    private var filteredPendingDrafts: [PostcardDraft] {
        guard let friendID else { return pendingDrafts }
        return pendingDrafts.filter { $0.toUserID == friendID }
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

    private func displayCityName(for item: BackendPostcardMessageDTO) -> String {
        let name = item.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        // Fallback: extract from cityID key "Name|ISO2"
        return item.cityID.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    private func displayCityName(for draft: PostcardDraft) -> String {
        let name = draft.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return draft.cityID.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
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

    private func fallbackDisplayName(for userID: String) -> String? {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let friend = socialStore.friends.first(where: { $0.id == trimmed }) else {
            return nil
        }
        let displayName = friend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return nil }
        return displayName
    }

    private func refreshInbox() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await postcardCenter.refreshFromBackend(token: sessionStore.currentAccessToken)
    }

    private func statusTone(for status: PostcardDraftStatus) -> Color {
        switch status {
        case .sending:
            return .orange
        case .failed:
            return .red
        case .sent:
            return .green
        case .draft:
            return FigmaTheme.subtext
        }
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
    let photoURL: String?
    let avatarLoadout: RobotLoadout
    let sentDate: Date
    let metaLabel: String
    var statusBadge: String? = nil
    var statusDetail: String? = nil
    var statusTone: Color = .orange
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil
    var messageID: String? = nil
    var token: String? = nil
    var reaction: PostcardReaction? = nil

    @State private var isFront = true
    @State private var saveToastText: String?
    @State private var showFullImage = false
    @State private var postcardViewID = UUID()
    @State private var showEmojiPicker = false
    @State private var showCommentInput = false
    @State private var reactionExpanded = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                FlippablePostcardView(
                    cityName: cityName,
                    nickname: nickname,
                    messageText: messageText,
                    photoSource: photoSource,
                    avatarLoadout: avatarLoadout,
                    isFront: $isFront,
                    sentDate: sentDate,
                    onLongPress: {
                        Task { await saveCurrentFaceToPhotos() }
                    }
                )

                if isFront, let _ = photoURL {
                    Button {
                        showFullImage = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .appMinTapTarget()
                    }
                }
            }

            HStack(spacing: 8) {
                Text(metaLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let statusBadge {
                    Text(statusBadge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusTone)
                }
                Text(sentDate, style: .date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.horizontal, 4)

            if statusDetail != nil || retryTitle != nil {
                HStack(spacing: 10) {
                    if let statusDetail {
                        Text(statusDetail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(statusTone)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    if let retryTitle, let onRetry {
                        Button(retryTitle, action: onRetry)
                            .font(.system(size: 12, weight: .bold))
                            .buttonStyle(.plain)
                            .foregroundColor(FigmaTheme.primary)
                    }
                }
                .padding(.horizontal, 4)
            }

            if let reaction {
                VStack(alignment: .leading, spacing: 6) {
                    if let emoji = reaction.reactionEmoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 20))
                    } else if reaction.viewedAt != nil {
                        Text("✓ \(L10n.t("postcard_viewed"))")
                            .font(.system(size: 11))
                            .foregroundColor(FigmaTheme.subtext)
                    }

                    if let comment = reaction.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 12))
                            .foregroundColor(FigmaTheme.text)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if messageID != nil && token != nil {
                HStack(spacing: 8) {
                    Button {
                        withAnimation { showEmojiPicker.toggle() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(FigmaTheme.text)
                            .appMinTapTarget()
                    }

                    if showEmojiPicker {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(["❤️", "👍", "😂", "😮", "🔥", "👏", "🎉", "😍", "🤔", "👀"], id: \.self) { emoji in
                                    Button(emoji) {
                                        Task { await sendReaction(emoji) }
                                        withAnimation { showEmojiPicker = false }
                                    }
                                    .font(.system(size: 24))
                                }
                                Button {
                                    showCommentInput = true
                                    showEmojiPicker = false
                                } label: {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 20))
                                        .foregroundColor(FigmaTheme.text)
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if let saveToastText {
                Text(saveToastText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
        .sheet(isPresented: $showFullImage) {
            if let photoURL {
                FullImageViewer(imageURL: photoURL)
            }
        }
        .sheet(isPresented: $showCommentInput) {
            if let messageID, let token {
                CommentInputSheet(messageID: messageID, token: token)
            }
        }
    }

    private func sendReaction(_ emoji: String) async {
        guard let messageID, let token else { return }
        let req = PostcardReactionRequest(reactionEmoji: emoji, comment: nil)
        do {
            try await BackendAPIClient.shared.reactToPostcard(token: token, messageID: messageID, req: req)
            await MainActor.run {
                saveToastText = String(format: L10n.t("reaction_sent"), emoji)
                clearSaveToastSoon()
            }
        } catch {
            await MainActor.run {
                saveToastText = L10n.t("postcard_send_failed")
                clearSaveToastSoon()
            }
        }
    }

    private func saveCurrentFaceToPhotos() async {
        guard #available(iOS 16.0, *) else {
            await MainActor.run {
                saveToastText = L10n.t("save_failed")
                clearSaveToastSoon()
            }
            return
        }

        let loadedSource: PostcardPhotoSource
        if case .remoteURL(let urlString) = photoSource,
           let url = URL(string: urlString),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            loadedSource = .uiImage(image)
        } else {
            loadedSource = photoSource
        }

        guard let image = renderFaceImage(isFront: isFront, photoSource: loadedSource) else {
            await MainActor.run {
                saveToastText = L10n.t("save_failed")
                clearSaveToastSoon()
            }
            return
        }

        await MainActor.run {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            saveToastText = isFront ? L10n.t("postcard_saved_front") : L10n.t("postcard_saved_back")
            clearSaveToastSoon()
        }
    }

    @available(iOS 16.0, *)
    private func renderFaceImage(isFront: Bool, photoSource: PostcardPhotoSource) -> UIImage? {
        let width: CGFloat = 540
        let height: CGFloat = width / (3.0 / 2.0)

        let faceView: AnyView
        if isFront {
            faceView = AnyView(
                PostcardFrontFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    photoSource: photoSource,
                    avatarLoadout: avatarLoadout,
                    cornerRadius: 0
                )
            )
        } else {
            faceView = AnyView(
                PostcardBackFaceView(
                    cityName: cityName,
                    nickname: nickname,
                    messageText: messageText,
                    avatarLoadout: avatarLoadout,
                    sentDate: sentDate,
                    cornerRadius: 0
                )
            )
        }

        let renderView = faceView
            .frame(width: width, height: height)

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

// MARK: - Comment Input Sheet

private struct CommentInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let messageID: String
    let token: String
    @State private var commentText = ""
    @State private var isSending = false
    @State private var sendFailed = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField(L10n.t("postcard_comment_placeholder"), text: $commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                    .padding()

                Text("\(commentText.count)/50")
                    .font(.system(size: 12))
                    .foregroundColor(commentText.count > 50 ? .red : FigmaTheme.subtext)

                if sendFailed {
                    Text(L10n.t("postcard_send_failed"))
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .navigationTitle(L10n.t("postcard_add_comment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("send")) {
                        Task { await sendComment() }
                    }
                    .disabled(commentText.isEmpty || commentText.count > 50 || isSending)
                }
            }
        }
    }

    private func sendComment() async {
        isSending = true
        let req = PostcardReactionRequest(reactionEmoji: nil, comment: commentText)
        do {
            try await BackendAPIClient.shared.reactToPostcard(token: token, messageID: messageID, req: req)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                isSending = false
                sendFailed = true
            }
        }
    }
}

// MARK: - Full Image Viewer

private struct FullImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let imageURL: String
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var saveToast = false
    @State private var loadAttempt = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text(L10n.t("postcard_send_failed"))
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                    Button {
                        loadFailed = false
                        loadAttempt += 1
                    } label: {
                        Text(L10n.t("retry"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    AppCloseButton(style: .circleDark) {
                        dismiss()
                    }
                    .padding()
                }
                Spacer()
                if image != nil {
                    Button {
                        if let image {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saveToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                saveToast = false
                            }
                        }
                    } label: {
                        Text(L10n.t("postcard_save_original"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }

            if saveToast {
                VStack {
                    Spacer()
                    Text(L10n.t("postcard_saved_to_album"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.bottom, 120)
                }
            }
        }
        .task(id: loadAttempt) {
            guard let url = URL(string: imageURL) else {
                loadFailed = true
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let loaded = UIImage(data: data) {
                    image = loaded
                } else {
                    loadFailed = true
                }
            } catch {
                loadFailed = true
            }
        }
    }
}
