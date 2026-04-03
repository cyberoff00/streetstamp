import SwiftUI

struct JourneyPrivacyOptionsSheet: View {
    let journey: JourneyRoute
    let onApply: (Set<JourneyPrivacyOption>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trimEndpoints: Bool
    @State private var hideLandmarks: Bool

    init(journey: JourneyRoute, onApply: @escaping (Set<JourneyPrivacyOption>) -> Void) {
        self.journey = journey
        self.onApply = onApply
        _trimEndpoints = State(initialValue: journey.privacyOptions.contains(.trimEndpoints))
        _hideLandmarks = State(initialValue: journey.privacyOptions.contains(.hideLandmarks))
    }

    private var hasAny: Bool { trimEndpoints || hideLandmarks }

    var body: some View {
        JourneySheetScaffold(
            title: L10n.t("privacy_toggle_title"),
            subtitle: L10n.t("privacy_description")
        ) {
            VStack(spacing: 8) {
                toggleRow(title: L10n.t("privacy_trim_endpoints"), isOn: $trimEndpoints)
                toggleRow(title: L10n.t("privacy_hide_landmarks"), isOn: $hideLandmarks)
            }

            Button(action: applyAndDismiss) {
                Text(L10n.t("save"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(UITheme.softBlack)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .appFullSurfaceTapTarget(.roundedRect(16))
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(UITheme.softBlack)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(UITheme.accent)
                .scaleEffect(0.88)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func applyAndDismiss() {
        var opts = Set<JourneyPrivacyOption>()
        if trimEndpoints { opts.insert(.trimEndpoints) }
        if hideLandmarks { opts.insert(.hideLandmarks) }
        onApply(opts)
        dismiss()
    }
}
