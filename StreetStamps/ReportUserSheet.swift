import SwiftUI

struct ReportUserSheet: View {
    let friendName: String
    @Binding var reason: String
    @Binding var detail: String
    let isSubmitting: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private var reasons: [(key: String, label: String)] {
        [
            ("spam", L10n.t("report_reason_spam")),
            ("harassment", L10n.t("report_reason_harassment")),
            ("inappropriate", L10n.t("report_reason_inappropriate")),
            ("other", L10n.t("report_reason_other")),
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: L10n.t("report_description"), friendName))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(reasons, id: \.key) { item in
                        Button {
                            reason = item.key
                        } label: {
                            HStack {
                                Text(item.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(FigmaTheme.text)
                                Spacer()
                                if reason == item.key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(FigmaTheme.primary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)

                        if item.key != reasons.last?.key {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)

                if reason == "other" {
                    TextField(L10n.t("report_detail_placeholder"), text: $detail, axis: .vertical)
                        .font(.system(size: 14))
                        .lineLimit(3...5)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
            .padding(.top, 12)
            .background(FigmaTheme.background)
            .navigationTitle(L10n.t("report_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("report_submit")) { onSubmit() }
                        .disabled(reason.isEmpty || isSubmitting)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
