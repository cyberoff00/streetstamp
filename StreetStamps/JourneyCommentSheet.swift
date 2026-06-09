import SwiftUI

/// Sheet that presents the comment threads for a journey. Two layouts:
///
/// - **Viewer mode** (`mode == .viewer`): a single thread between the viewer
///   and the journey owner. Messages scroll; the composer is pinned to the
///   bottom of the sheet so the empty state can breathe in the middle.
/// - **Owner mode** (`mode == .owner`): one section per friend who has
///   started a thread. Each section keeps its own inline composer so replies
///   target the right friend.
struct JourneyCommentSheet: View {
    enum Mode {
        case viewer(ownerID: String, ownerDisplayName: String?)
        case owner
    }

    let journeyID: String
    let mode: Mode
    let viewerID: String
    /// Owner multi-thread only: scroll the block of the friend who fired a
    /// comment deep link into view. nil for normal opens / viewer mode.
    var focusSenderID: String? = nil

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var socialStore: SocialGraphStore
    @Environment(\.dismiss) private var dismiss

    @State private var hasLoadedInitial = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t("journey_comments_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.t("done")) { dismiss() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WorldoPalette.inkSecondary)
                    }
                }
        }
        // Start compact; user can drag up when the thread gets long.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard !hasLoadedInitial else { return }
            hasLoadedInitial = true
            await loadInitial()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .viewer(let ownerID, let ownerName):
            JourneyCommentViewerLayout(
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: ownerID,
                otherDisplayName: ownerName,
                viewerID: viewerID
            )
        case .owner:
            ownerContent
        }
    }

    @ViewBuilder
    private var ownerContent: some View {
        let threads = store.threads(forJourney: journeyID)
        if threads.isEmpty {
            Group {
                switch store.threadsLoadPhase(forJourney: journeyID) {
                case .idle, .loading:
                    JourneyCommentLoadingState()
                case .failed:
                    JourneyCommentErrorState {
                        Task {
                            await store.loadThreads(
                                journeyID: journeyID,
                                token: sessionStore.currentAccessToken
                            )
                        }
                    }
                case .loaded:
                    JourneyCommentEmptyState(message: L10n.t("journey_comments_empty_owner"))
                }
            }
            .background(FigmaTheme.background.ignoresSafeArea())
        } else if threads.count == 1, let thread = threads.first {
            // Common case — single friend's thread. Render like viewer mode so
            // the composer stays pinned at the bottom of the sheet.
            JourneyCommentViewerLayout(
                journeyID: journeyID,
                ownerID: thread.ownerID,
                otherUserID: thread.otherUserID,
                otherDisplayName: resolvedFriendName(for: thread),
                viewerID: viewerID
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(Array(threads.enumerated()), id: \.element.id) { idx, thread in
                            VStack(spacing: 14) {
                                if idx > 0 {
                                    Divider().background(WorldoPalette.hairline.opacity(0.5))
                                }
                                JourneyCommentThreadBlockView(
                                    journeyID: journeyID,
                                    ownerID: thread.ownerID,
                                    otherUserID: thread.otherUserID,
                                    otherDisplayName: resolvedFriendName(for: thread),
                                    viewerID: viewerID
                                )
                            }
                            .padding(.horizontal, 16)
                            // Anchor each block by the friend's user ID so a
                            // deep link can scroll to the right conversation.
                            .id(thread.otherUserID)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(FigmaTheme.background.ignoresSafeArea())
                .onAppear { scrollToFocusedThread(using: proxy, threads: threads) }
            }
        }
    }

    private func resolvedFriendName(for thread: JourneyCommentThread) -> String? {
        if let name = thread.otherDisplayName, !name.isEmpty { return name }
        return socialStore.friends.first(where: { $0.id == thread.otherUserID })?.displayName
    }

    private func scrollToFocusedThread(using proxy: ScrollViewProxy, threads: [JourneyCommentThread]) {
        guard let target = focusSenderID,
              threads.contains(where: { $0.otherUserID == target }) else { return }
        // Let the lazy stack lay out before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func loadInitial() async {
        let token = sessionStore.currentAccessToken
        switch mode {
        case .viewer(let ownerID, _):
            await store.loadMessages(journeyID: journeyID, otherUserID: ownerID, token: token)
            await store.markRead(journeyID: journeyID, otherUserID: ownerID, token: token)
        case .owner:
            await store.loadThreads(journeyID: journeyID, token: token)
        }
    }
}

// MARK: - Viewer-mode layout

/// Full-sheet layout for a single thread: messages fill the available space
/// (centered empty state when nothing yet), composer pinned at the bottom.
private struct JourneyCommentViewerLayout: View {
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let otherDisplayName: String?
    let viewerID: String

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var socialStore: SocialGraphStore

    private var threadKey: String {
        JourneyCommentThreadKey.make(journeyID: journeyID, userA: viewerID, userB: otherUserID)
    }

    private var messages: [JourneyComment] {
        store.messages(forThread: threadKey)
    }

    private var hasMessages: Bool { !messages.isEmpty }

    private var resolvedOtherName: String {
        if let name = otherDisplayName, !name.isEmpty { return name }
        if let name = socialStore.friends.first(where: { $0.id == otherUserID })?.displayName,
           !name.isEmpty { return name }
        return L10n.t("friend")
    }

    private let bottomAnchorID = "__journey_comments_bottom__"

    var body: some View {
        Group {
            if hasMessages {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(resolvedOtherName.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundColor(WorldoPalette.inkSecondary)

                            JourneyCommentMessagesList(
                                journeyID: journeyID,
                                ownerID: ownerID,
                                otherUserID: otherUserID,
                                otherDisplayName: otherDisplayName,
                                viewerID: viewerID
                            )

                            Color.clear.frame(height: 1).id(bottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                    // Scroll to the newest message only when the *last* message
                    // changes (a new arrival or an optimistic send). Watching the
                    // raw count would also fire when older messages are paged in
                    // at the top, yanking the user back to the bottom.
                    .onChange(of: messages.last?.id) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
            } else {
                // No messages cached: distinguish "still loading" / "failed" /
                // "genuinely empty" so a network failure doesn't masquerade as
                // an empty thread.
                switch store.messageLoadPhase(forThread: threadKey) {
                case .idle, .loading:
                    JourneyCommentLoadingState()
                case .failed:
                    JourneyCommentErrorState { Task { await loadAndMarkRead() } }
                case .loaded:
                    JourneyCommentEmptyState(message: L10n.t("journey_comments_empty_thread"))
                }
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        // Load the thread's messages whether or not any are cached yet. The
        // empty-state branch above does NOT contain `JourneyCommentMessagesList`,
        // so its load `.task` never mounts — owner-mode single-thread (the most
        // common case) would otherwise stay blank forever. Attaching the load
        // here covers both branches. Idempotent: the store guards in-flight
        // fetches, and the inner list's task skips when messages already exist.
        .task(id: threadKey) {
            guard messages.isEmpty else { return }
            await loadAndMarkRead()
        }
        .safeAreaInset(edge: .bottom) {
            JourneyCommentComposer(
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: otherUserID,
                otherDisplayName: otherDisplayName,
                viewerID: viewerID,
                showFriendNameInPlaceholder: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                FigmaTheme.background
                    .overlay(
                        Divider().opacity(0.4),
                        alignment: .top
                    )
            )
        }
    }

    private func loadAndMarkRead() async {
        let token = sessionStore.currentAccessToken
        await store.loadMessages(journeyID: journeyID, otherUserID: otherUserID, token: token)
        await store.markRead(journeyID: journeyID, otherUserID: otherUserID, token: token)
    }
}

// MARK: - Owner-mode thread block

/// One friend's thread inside the owner sheet. Header (friend name) +
/// inline messages + inline composer.
struct JourneyCommentThreadBlockView: View {
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let otherDisplayName: String?
    let viewerID: String

    private var displayName: String {
        if let name = otherDisplayName, !name.isEmpty { return name }
        return L10n.t("friend")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(WorldoPalette.inkSecondary)

            JourneyCommentMessagesList(
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: otherUserID,
                otherDisplayName: otherDisplayName,
                viewerID: viewerID
            )

            JourneyCommentComposer(
                journeyID: journeyID,
                ownerID: ownerID,
                otherUserID: otherUserID,
                otherDisplayName: otherDisplayName,
                viewerID: viewerID,
                showFriendNameInPlaceholder: true
            )
            .padding(.top, 2)
        }
    }
}

// MARK: - Messages list (shared by viewer & owner)

private struct JourneyCommentMessagesList: View {
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let otherDisplayName: String?
    let viewerID: String

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    private var threadKey: String {
        JourneyCommentThreadKey.make(journeyID: journeyID, userA: viewerID, userB: otherUserID)
    }

    private var allMessages: [JourneyComment] {
        store.messages(forThread: threadKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if allMessages.isEmpty {
                switch store.messageLoadPhase(forThread: threadKey) {
                case .idle, .loading:
                    JourneyCommentInlineLoading()
                case .failed:
                    JourneyCommentInlineError { Task { await loadAndMarkRead() } }
                case .loaded:
                    // A thread with no messages shouldn't normally surface in
                    // the owner list; render nothing and let the composer show.
                    EmptyView()
                }
            } else {
                if store.hasMoreOlder(forThread: threadKey) {
                    Button {
                        Task { await loadOlder() }
                    } label: {
                        Group {
                            if store.isLoadingOlder(forThread: threadKey) {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(L10n.t("journey_comments_load_older"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(WorldoPalette.signal)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(allMessages) { msg in
                    JourneyCommentRow(
                        message: msg,
                        isOwnMessage: msg.senderID == viewerID,
                        otherDisplayName: otherDisplayName,
                        otherUserID: otherUserID,
                        onRetry: msg.sendState == .failed ? { Task { await retry(msg) } } : nil
                    )
                }
            }
        }
        // Always refresh on appear — NOT just when empty. A cached thread would
        // otherwise never pick up comments that arrived since the last open
        // (the push handler refreshes only the thread/unread summaries, never
        // `messagesByThread`), and markRead would never re-run — leaving the
        // newest message hidden and the unread badge stuck red. `loadMessages`
        // dedupes in-flight fetches and replaces with the latest page; markRead
        // is cheap and idempotent.
        .task(id: threadKey) {
            await loadAndMarkRead()
        }
    }

    private func loadAndMarkRead() async {
        let token = sessionStore.currentAccessToken
        await store.loadMessages(journeyID: journeyID, otherUserID: otherUserID, token: token)
        await store.markRead(journeyID: journeyID, otherUserID: otherUserID, token: token)
    }

    private func loadOlder() async {
        await store.loadOlderMessages(
            journeyID: journeyID,
            otherUserID: otherUserID,
            token: sessionStore.currentAccessToken
        )
    }

    private func retry(_ message: JourneyComment) async {
        await store.retrySend(message, token: sessionStore.currentAccessToken)
    }
}

// MARK: - Composer (shared)

private struct JourneyCommentComposer: View {
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let otherDisplayName: String?
    let viewerID: String
    /// Owner mode wants "Reply to <friend>…"; viewer mode prefers a neutral
    /// "Add a comment…" since there is only one thread on screen.
    let showFriendNameInPlaceholder: Bool

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var draftText: String = ""
    @FocusState private var inputFocused: Bool

    private var placeholder: String {
        if showFriendNameInPlaceholder {
            let name = (otherDisplayName?.isEmpty == false) ? otherDisplayName! : L10n.t("friend")
            return String(format: L10n.t("journey_comments_reply_placeholder"), name)
        }
        return L10n.t("journey_comments_add_placeholder")
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                TextField(placeholder, text: $draftText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .font(.system(size: 14))
                    .foregroundColor(WorldoPalette.inkPrimary)
                    .onChange(of: draftText) { _, newValue in
                        if newValue.count > JourneyCommentLimits.maxContentLength {
                            draftText = String(newValue.prefix(JourneyCommentLimits.maxContentLength))
                        }
                    }

                if canSend {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(WorldoPalette.signal))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(FigmaTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 0.5)
            )
            .animation(.easeOut(duration: 0.15), value: canSend)
        }
    }

    private func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Optimistic: clear the field right away. `store.send` inserts the
        // bubble synchronously in a `.sending` state before the network call,
        // and the bubble itself surfaces the retry affordance on failure — so
        // the composer no longer waits on, or reports, the round-trip.
        draftText = ""
        inputFocused = false
        // Viewer sends to owner; owner replies to the other party in this thread.
        let recipientID = (viewerID == ownerID) ? otherUserID : ownerID
        _ = try? await store.send(
            journeyID: journeyID,
            ownerID: ownerID,
            recipientID: recipientID,
            content: text,
            token: sessionStore.currentAccessToken
        )
    }
}

// MARK: - Empty state

private struct JourneyCommentEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(WorldoPalette.inkSecondary.opacity(0.6))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(WorldoPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading / error states

/// Full-size centered spinner, sized to match `JourneyCommentEmptyState` so the
/// sheet doesn't jump when the load resolves into a list or empty state.
private struct JourneyCommentLoadingState: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-size error state with a retry affordance. Shown when an initial load
/// fails, so a network error is never mistaken for "no comments".
private struct JourneyCommentErrorState: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(WorldoPalette.inkSecondary.opacity(0.6))
            Text(L10n.t("journey_comments_load_failed"))
                .font(.system(size: 13))
                .foregroundColor(WorldoPalette.inkSecondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(L10n.t("retry"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WorldoPalette.signal)
            }
            .buttonStyle(.plain)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact spinner for an owner thread block (inline, left-aligned).
private struct JourneyCommentInlineLoading: View {
    var body: some View {
        HStack {
            ProgressView()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Compact error + retry for an owner thread block.
private struct JourneyCommentInlineError: View {
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.t("journey_comments_load_failed"))
                .font(.system(size: 12))
                .foregroundColor(WorldoPalette.inkSecondary)
            Button(action: retry) {
                Text(L10n.t("retry"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WorldoPalette.signal)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Comment row (Instagram-style)

struct JourneyCommentRow: View {
    let message: JourneyComment
    let isOwnMessage: Bool
    let otherDisplayName: String?
    /// The other party's user ID for this thread — used as a fallback lookup
    /// when `message.senderID` isn't in the local friends list (e.g. the
    /// signed-in viewer's own ID).
    let otherUserID: String
    /// Set only for a `.failed` optimistic message; taps re-send it.
    var onRetry: (() -> Void)? = nil

    @EnvironmentObject private var socialStore: SocialGraphStore
    @AppStorage("streetstamps.profile.displayName") private var ownDisplayName: String = "EXPLORER"
    @State private var ownLoadout: RobotLoadout = AvatarLoadoutStore.load()

    private var friendProfile: FriendProfileSnapshot? {
        socialStore.friends.first(where: { $0.id == message.senderID })
            ?? socialStore.friends.first(where: { $0.id == otherUserID })
    }

    private var senderName: String {
        if isOwnMessage {
            let trimmed = ownDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? L10n.t("journey_comments_you") : trimmed
        }
        if let name = friendProfile?.displayName, !name.isEmpty { return name }
        if let name = otherDisplayName, !name.isEmpty { return name }
        return L10n.t("friend")
    }

    private var senderLoadout: RobotLoadout {
        if isOwnMessage { return ownLoadout.normalizedForCurrentAvatar() }
        if let loadout = friendProfile?.loadout { return loadout.normalizedForCurrentAvatar() }
        return RobotLoadout.defaultBoy
    }

    private var timeLabel: String {
        Self.timeFormatter.localizedString(for: message.createdAt, relativeTo: Date())
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RobotRendererView(size: 34, face: .front, loadout: senderLoadout)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .background(
                    Circle().fill(WorldoPalette.signal.opacity(0.12))
                )
                .onReceive(NotificationCenter.default.publisher(for: .avatarLoadoutDidChange)) { _ in
                    if isOwnMessage { ownLoadout = AvatarLoadoutStore.load() }
                }

            VStack(alignment: .leading, spacing: 2) {
                // Name + body share one wrapping Text so the body flows
                // naturally after the name, IG-style.
                (Text(senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WorldoPalette.inkPrimary)
                 + Text("  ")
                 + Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(WorldoPalette.inkPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(message.sendState == .sending ? 0.55 : 1.0)

                statusLine
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch message.sendState {
        case .sending:
            Text(L10n.t("journey_comments_sending"))
                .font(.system(size: 11))
                .foregroundColor(WorldoPalette.inkSecondary)
        case .failed:
            Button { onRetry?() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                    Text(L10n.t("journey_comments_send_failed_retry"))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(WorldoPalette.terracotta)
            }
            .buttonStyle(.plain)
        case .sent:
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundColor(WorldoPalette.inkSecondary)
        }
    }
}
