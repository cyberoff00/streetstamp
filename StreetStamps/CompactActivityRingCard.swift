import SwiftUI

struct CompactActivityRingCard: View {
    let stats: ProfileStatsSnapshot
    let levelProgress: UserLevelProgress
    let journeyDates: [Date]
    var onCardsTap: (() -> Void)? = nil
    var onMemoriesTap: (() -> Void)? = nil
    var showStatsPanel: Bool = true

    @State private var showRingHelp = false

    private let accentBlue = FigmaTheme.primary
    private let softBlue = FigmaTheme.primary.opacity(0.12)

    var body: some View {
        VStack(spacing: 20) {
            if showStatsPanel {
                statsPanel
            }
            activityPanel
        }
        .frame(maxWidth: .infinity)
        .alert(
            String(format: L10n.t("activity_ring_next_level_hint"), levelProgress.journeysRemainingToNextLevel),
            isPresented: $showRingHelp
        ) {
            Button(L10n.t("ok"), role: .cancel) {}
        }
    }

    private var activityPanel: some View {
        HStack(alignment: .center, spacing: 20) {
            progressRing

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1, height: 60)

            MiniJourneyHeatmap(journeyDates: journeyDates, accentBlue: accentBlue)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        .overlay(alignment: .bottomLeading) {
            Button { showRingHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 18, height: 18)
                    .background(Color(red: 0.97, green: 0.97, blue: 0.98))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private var statsPanel: some View {
        HStack(spacing: 0) {
            statItem(value: "\(stats.totalJourneys)", label: L10n.upper("activity_stat_journeys"), color: FigmaTheme.text, tappable: false, action: nil)
            statDivider
            statItem(value: String(format: "%02d", stats.totalUnlockedCities), label: L10n.upper("activity_stat_cards"), color: accentBlue, tappable: true, action: onCardsTap)
            statDivider
            statItem(value: "\(stats.totalMemories)", label: L10n.upper("activity_stat_memories"), color: accentBlue, tappable: true, action: onMemoriesTap)
            statDivider
            statItem(value: String(format: "%.0f", stats.totalDistance / 1000.0), label: L10n.upper("activity_stat_distance_km"), color: FigmaTheme.text, tappable: false, action: nil)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    private var progressRing: some View {
        let ringSize: CGFloat = 96
        let lineWidth: CGFloat = 10
        return ZStack {
            Circle()
                .stroke(softBlue, lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            Circle().trim(from: 0, to: CGFloat(levelProgress.progress))
                .stroke(
                    accentBlue,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("LV.\(levelProgress.level)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                Text(progressPercentText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }
        }
        .frame(width: ringSize + 8, height: ringSize + 8)
    }

    private var progressPercentText: String {
        "\(Int(levelProgress.progress * 100))%"
    }

    private func statItem(value: String, label: String, color: Color, tappable: Bool, action: (() -> Void)?) -> some View {
        let content = VStack(spacing: 8) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(color.opacity(0.45))
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)

        return Group {
            if tappable, let action {
                Button(action: action) {
                    content
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var statDivider: some View {
        Rectangle().fill(Color.gray.opacity(0.12)).frame(width: 1, height: 36)
    }
}

// MARK: - Mini Journey Heatmap

struct MiniJourneyHeatmap: View {
    let journeyDates: [Date]
    let accentBlue: Color

    @State private var displayMonth: Date = Date()

    private let cal = Calendar.current
    private let weekdays = Calendar.current.veryShortStandaloneWeekdaySymbols

    private var journeyDaySet: Set<DateComponents> {
        Set(journeyDates.map { cal.dateComponents([.year, .month, .day], from: $0) })
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        if Locale.current.identifier.hasPrefix("zh") {
            fmt.dateFormat = "M 月"
        } else {
            fmt.setLocalizedDateFormatFromTemplate("MMM")
        }
        return fmt.string(from: displayMonth)
    }

    private func hasJourney(on date: Date) -> Bool {
        let dc = cal.dateComponents([.year, .month, .day], from: date)
        return journeyDaySet.contains(dc)
    }

    var body: some View {
        let days = JourneyMemoryCalendarDay.daysForMonth(displayMonth)
        let today = cal.startOfDay(for: Date())

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.35))
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(minWidth: 42)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days) { day in
                    dayBlock(day, today: today)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayBlock(_ day: JourneyMemoryCalendarDay, today: Date) -> some View {
        Group {
            if let date = day.date {
                let journey = hasJourney(on: date)
                let isToday = cal.isDate(date, inSameDayAs: today)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(journey ? accentBlue.opacity(0.45) : accentBlue.opacity(0.08))
                    .overlay {
                        if isToday && !journey {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(accentBlue.opacity(0.32), lineWidth: 1)
                        }
                    }
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(minWidth: 20, minHeight: 20)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = next
        }
    }
}
