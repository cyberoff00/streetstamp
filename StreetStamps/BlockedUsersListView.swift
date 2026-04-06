import SwiftUI

struct BlockedUsersListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var blockStore: UserBlockStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    var body: some View {
        List {
            if blockStore.blockedUsers.isEmpty {
                Text(L10n.t("blocked_users_empty"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 40)
            } else {
                ForEach(blockStore.blockedUsers) { user in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(FigmaTheme.text)
                            if let handle = user.handle, !handle.isEmpty {
                                Text("@\(handle)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.subtext)
                            }
                        }

                        Spacer()

                        Button(L10n.t("unblock")) {
                            Task {
                                try? await blockStore.unblockUser(user.id, accessToken: sessionStore.currentAccessToken)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: L10n.t("settings_blocked_users_row"),
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 18,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await blockStore.refresh(accessToken: sessionStore.currentAccessToken)
        }
    }
}
