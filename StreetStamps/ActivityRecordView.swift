import SwiftUI

struct ActivityRecordView: View {
    @Environment(\.dismiss) private var dismiss
    let displayName: String
    let stats: ProfileStatsSnapshot
    let levelProgress: UserLevelProgress
    let loadout: RobotLoadout

    @State private var showRingHelp = false

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 40) {
                        ringChart
                        userNameSection
                        statsGrid
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 60)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .alert(L10n.t("activity_ring_help"), isPresented: $showRingHelp) {
            Button(L10n.t("ok"), role: .cancel) {}
        }
    }

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.t("activity_record_title"))
                .navigationTitleStyle(level: .secondary)
                .tracking(0.2)

            Spacer()

            Button {
                showRingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text.opacity(0.5))
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FigmaTheme.border).frame(height: 1)
        }
    }

    private var ringChart: some View {
        let memoryProgress = Double(stats.totalMemories % 50) / 50.0
        let cityProgress = Double(stats.totalUnlockedCities % 10) / 10.0

        return ZStack {
            Circle().stroke(Color(white: 0.95), lineWidth: 24).frame(width: 200, height: 200)
            Circle().trim(from: 0, to: CGFloat(levelProgress.progress))
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.8, blue: 0.5), Color(red: 0.15, green: 0.65, blue: 0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 24, lineCap: .round)
                )
                .frame(width: 200, height: 200).rotationEffect(.degrees(-90))

            Circle().stroke(Color(white: 0.95), lineWidth: 20).frame(width: 160, height: 160)
            Circle().trim(from: 0, to: CGFloat(memoryProgress))
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 1.0, green: 0.6, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 160, height: 160).rotationEffect(.degrees(-90))

            Circle().stroke(Color(white: 0.95), lineWidth: 16).frame(width: 120, height: 120)
            Circle().trim(from: 0, to: CGFloat(cityProgress))
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.6, blue: 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 120, height: 120).rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("LV.\(levelProgress.level)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                Text("\(Int(levelProgress.progress * 100))%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
    }

    private var userNameSection: some View {
        HStack(spacing: 10) {
            Text(displayName).font(.system(size: 24, weight: .bold))
            RobotRendererView(size: 28, face: .front, loadout: loadout).frame(width: 28, height: 28)
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statBox(value: "\(stats.totalJourneys)", label: L10n.upper("activity_stat_journeys"))
                Divider().frame(height: 90)
                statBox(value: "\(stats.totalMemories)", label: L10n.upper("activity_stat_memories"))
            }
            Divider()
            HStack(spacing: 0) {
                statBox(value: String(format: "%02d", stats.totalUnlockedCities), label: L10n.upper("activity_stat_cards"))
                Divider().frame(height: 90)
                statBox(value: String(format: "%.0f", stats.totalDistance / 1000.0), label: L10n.upper("activity_stat_distance_km"))
            }
        }
        .padding(.horizontal, 20)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 10) {
            Text(value).font(.system(size: 42, weight: .bold))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(.gray).tracking(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }
}
