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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.t("privacy_toggle_title"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(L10n.t("save")) {
                    applyAndDismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black)
            }
            .padding(.top, 8)

            Text(L10n.t("privacy_description"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                checkRow(
                    title: L10n.t("privacy_trim_endpoints"),
                    isOn: $trimEndpoints
                )
                checkRow(
                    title: L10n.t("privacy_hide_landmarks"),
                    isOn: $hideLandmarks
                )
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func checkRow(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(isOn.wrappedValue ? .black : .black.opacity(0.3))
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.black.opacity(0.8))
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func applyAndDismiss() {
        var opts = Set<JourneyPrivacyOption>()
        if trimEndpoints { opts.insert(.trimEndpoints) }
        if hideLandmarks { opts.insert(.hideLandmarks) }
        onApply(opts)
        dismiss()
    }
}
