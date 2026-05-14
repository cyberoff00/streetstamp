import SwiftUI

/// Sheet that presents the comment threads for a journey. Two layouts:
///
/// - **Viewer mode** (`mode == .viewer`): a single block containing the
///   conversation between the active user and the journey owner. If no
///   thread exists yet, the input box lets the viewer post the first
///   message, which creates the thread.
/// - **Owner mode** (`mode == .owner`): a stack of blocks, one per friend
///   who has started a thread on this journey. Each block is self-contained
///   with its own inline reply input.
struct JourneyCommentSheet: View {
    enum Mode {
        case viewer(ownerID: String, ownerDisplayName: String?)
        case owner
    }

    let journeyID: String
    let mode: Mode
    let viewerID: String

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore
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
                    }
                }
        }
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    JourneyCommentThreadBlockView(
                        journeyID: journeyID,
                        ownerID: ownerID,
                        otherUserID: ownerID,
                        otherDisplayName: ownerName,
                        viewerID: viewerID,
                        showHeader: false
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .background(FigmaTheme.background.ignoresSafeArea())
        case .owner:
            ownerContent
        }
    }

    @ViewBuilder
    private var ownerContent: some View {
        let threads = store.threads(forJourney: journeyID)
        if threads.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "bubble.left")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.secondary)
                Text(L10n.t("journey_comments_empty_owner"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(FigmaTheme.background.ignoresSafeArea())
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(threads) { thread in
                        JourneyCommentThreadBlockView(
                            journeyID: journeyID,
                            ownerID: thread.ownerID,
                            otherUserID: thread.otherUserID,
                            otherDisplayName: thread.otherDisplayName,
                            viewerID: viewerID,
                            showHeader: true
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(FigmaTheme.background.ignoresSafeArea())
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

// MARK: - Thread block

/// A single self-contained conversation block: header (optional) + messages +
/// inline reply input. Used in both viewer single-block and owner multi-block
/// layouts. Each block manages its own input `@State` so multi-block typing
/// doesn't share text across friends.
struct JourneyCommentThreadBlockView: View {
    let journeyID: String
    let ownerID: String
    let otherUserID: String
    let otherDisplayName: String?
    let viewerID: String
    /// Whether to render the friend header strip. Owner multi-block layout
    /// shows it; viewer single-block hides it (the sheet title already says
    /// "Comments" and there's only one thread).
    let showHeader: Bool

    @EnvironmentObject private var store: JourneyCommentStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var draftText: String = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var isExpanded = false
    @FocusState private var inputFocused: Bool

    private var threadKey: String {
        JourneyCommentThreadKey.make(journeyID: journeyID, userA: viewerID, userB: otherUserID)
    }

    private var allMessages: [JourneyComment] {
        store.messages(forThread: threadKey)
    }

    private var visibleMessages: [JourneyComment] {
        let recent = 3
        if isExpanded || allMessages.count <= recent {
            return allMessages
        }
        return Array(allMessages.suffix(recent))
    }

    private var hiddenCount: Int {
        max(0, allMessages.count - visibleMessages.count)
    }

    private var displayName: String {
        if let name = otherDisplayName, !name.isEmpty { return name }
        return L10n.t("friend")
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                header
                Divider().opacity(0.3)
            }
            messagesArea
            replyInput
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 0.5)
        )
        .task(id: threadKey) {
            // Load this thread's messages if we don't have them yet. The
            // owner sheet pre-loaded the thread summary, but per-thread
            // messages are loaded lazily as blocks appear.
            if allMessages.isEmpty {
                let token = sessionStore.currentAccessToken
                await store.loadMessages(
                    journeyID: journeyID,
                    otherUserID: otherUserID,
                    token: token
                )
                await store.markRead(
                    journeyID: journeyID,
                    otherUserID: otherUserID,
                    token: token
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(initial(of: displayName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                )
            Text(displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var messagesArea: some View {
        if allMessages.isEmpty {
            HStack {
                Spacer()
                Text(L10n.t("journey_comments_empty_thread"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 8) {
                if hiddenCount > 0 {
                    Button {
                        withAnimation { isExpanded = true }
                    } label: {
                        Text(String(format: L10n.t("journey_comments_show_older"), hiddenCount))
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(visibleMessages) { msg in
                    JourneyCommentMessageBubble(
                        message: msg,
                        isOwnMessage: msg.senderID == viewerID
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var replyInput: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    String(format: L10n.t("journey_comments_reply_placeholder"), displayName),
                    text: $draftText,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .focused($inputFocused)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(FigmaTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: draftText) { _, newValue in
                    // Hard cap at the limit while typing to avoid silent
                    // truncation on send.
                    if newValue.count > JourneyCommentLimits.maxContentLength {
                        draftText = String(newValue.prefix(JourneyCommentLimits.maxContentLength))
                    }
                    if !newValue.isEmpty { sendError = nil }
                }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canSend ? .white : .gray)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canSend ? Color.black : Color.gray.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
            }

            if let sendError {
                HStack {
                    Text(sendError)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            // Recipient depends on who's sending: viewer sends to owner;
            // owner replies to the friend (the other user in this thread).
            let recipientID = (viewerID == ownerID) ? otherUserID : ownerID
            _ = try await store.send(
                journeyID: journeyID,
                ownerID: ownerID,
                recipientID: recipientID,
                content: text,
                token: sessionStore.currentAccessToken
            )
            draftText = ""
            inputFocused = false
        } catch {
            sendError = L10n.t("journey_comments_send_failed")
        }
    }

    private func initial(of name: String) -> String {
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Message bubble

struct JourneyCommentMessageBubble: View {
    let message: JourneyComment
    let isOwnMessage: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwnMessage { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(isOwnMessage ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOwnMessage ? Color.black : Color.gray.opacity(0.12))
                )
                .frame(maxWidth: 260, alignment: isOwnMessage ? .trailing : .leading)
            if !isOwnMessage { Spacer(minLength: 40) }
        }
    }
}
