import SwiftUI

struct PostcardInboxView: View {
    enum Box: String, CaseIterable, Identifiable {
        case sent = "Sent"
        case received = "Received"
        var id: String { rawValue }
    }

    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var postcardCenter: PostcardCenter

    @State private var selectedBox: Box = .sent

    var body: some View {
        VStack(spacing: 12) {
            Picker("Postcards", selection: $selectedBox) {
                ForEach(Box.allCases) { box in
                    Text(box.rawValue).tag(box)
                }
            }
            .pickerStyle(.segmented)

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
        .navigationTitle("Postcards")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await postcardCenter.refreshFromBackend(token: sessionStore.currentAccessToken)
        }
    }

    @ViewBuilder
    private var sentSection: some View {
        if postcardCenter.drafts.isEmpty {
            emptyState(text: "No sent postcards yet")
        } else {
            ForEach(postcardCenter.drafts) { draft in
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
                            Text("Retry")
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
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        if postcardCenter.receivedItems.isEmpty {
            emptyState(text: "No received postcards yet")
        } else {
            ForEach(postcardCenter.receivedItems) { item in
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

                    Text("From: \(item.fromDisplayName ?? item.fromUserID)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
            }
        }
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
