import SwiftUI

struct ProfileHeroActivitySummarySection: View {
    let levelProgress: UserLevelProgress
    let citiesCount: Int
    let memoriesCount: Int
    let journeyDates: [Date]

    @State private var showRingHelp = false

    private let accentBlue = FigmaTheme.primary

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            concentricRings

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(width: 1, height: 74)

            MiniJourneyHeatmap(journeyDates: journeyDates, accentBlue: accentBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
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
            .popover(isPresented: $showRingHelp, attachmentAnchor: .point(.center), arrowEdge: .bottom) {
                RingHelpPopover()
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    // MARK: - Concentric Rings

    private var concentricRings: some View {
        // Proportional to ActivityRecordView (200/160/120, lw 24/20/16)
        let outerD: CGFloat = 100
        let midD: CGFloat   = 76
        let innerD: CGFloat = 52

        let outerW: CGFloat = 13
        let midW: CGFloat   = 11
        let innerW: CGFloat = 9

        let trackColor = Color(white: 0.95)

        let levelFrac = CGFloat(levelProgress.progress)
        // Outer=level(green), Middle=memories/50(orange), Inner=cities/20(blue)
        // — same layer order as ActivityRecordView
        let memFrac  = CGFloat(min(1.0, Double(memoriesCount) / 50.0))
        let cityFrac = CGFloat(min(1.0, Double(citiesCount)   / 20.0))

        let greenGrad = LinearGradient(
            colors: [Color(red: 0.20, green: 0.80, blue: 0.50), Color(red: 0.15, green: 0.65, blue: 0.40)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        let orangeGrad = LinearGradient(
            colors: [Color(red: 1.00, green: 0.70, blue: 0.30), Color(red: 1.00, green: 0.60, blue: 0.20)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        let blueGrad = LinearGradient(
            colors: [Color(red: 0.40, green: 0.70, blue: 1.00), Color(red: 0.30, green: 0.60, blue: 0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        return ZStack {
            // ── Outer — level progress (green) ──
            Circle()
                .stroke(trackColor, lineWidth: outerW)
                .frame(width: outerD, height: outerD)
            Circle().trim(from: 0, to: levelFrac)
                .stroke(greenGrad, style: StrokeStyle(lineWidth: outerW, lineCap: .round))
                .frame(width: outerD, height: outerD)
                .rotationEffect(.degrees(-90))

            // ── Middle — memories / 50 (orange) ──
            Circle()
                .stroke(trackColor, lineWidth: midW)
                .frame(width: midD, height: midD)
            Circle().trim(from: 0, to: memFrac)
                .stroke(orangeGrad, style: StrokeStyle(lineWidth: midW, lineCap: .round))
                .frame(width: midD, height: midD)
                .rotationEffect(.degrees(-90))

            // ── Inner — cities / 20 (blue) ──
            Circle()
                .stroke(trackColor, lineWidth: innerW)
                .frame(width: innerD, height: innerD)
            Circle().trim(from: 0, to: cityFrac)
                .stroke(blueGrad, style: StrokeStyle(lineWidth: innerW, lineCap: .round))
                .frame(width: innerD, height: innerD)
                .rotationEffect(.degrees(-90))

            // ── Center ──
            VStack(spacing: 1) {
                Text("LV.\(levelProgress.level)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.gray)
                Text("\(Int(levelProgress.progress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
            }
        }
        .frame(width: outerD + 6, height: outerD + 6)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

private struct RingHelpRow: View {
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.15))
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }
}

private struct RingHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("activity_rings"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(white: 0.35))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                RingHelpRow(
                    color: Color(red: 0.20, green: 0.80, blue: 0.50),
                    title: L10n.t("ring_outer_title"),
                    subtitle: L10n.t("ring_outer_desc")
                )
                RingHelpRow(
                    color: Color(red: 1.00, green: 0.65, blue: 0.25),
                    title: L10n.t("ring_middle_title"),
                    subtitle: L10n.t("ring_middle_desc")
                )
                RingHelpRow(
                    color: Color(red: 0.35, green: 0.65, blue: 0.95),
                    title: L10n.t("ring_inner_title"),
                    subtitle: L10n.t("ring_inner_desc")
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 230)
    }
}
