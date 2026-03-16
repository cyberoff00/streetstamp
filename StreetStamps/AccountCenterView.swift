import SwiftUI

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var backendBaseURL = BackendConfig.baseURLString
    @State private var displayNameDraft = ""
    @State private var displayNameInput = ""
    @State private var isEditingDisplayName = false
    @State private var exclusiveIDDraft = ""
    @State private var exclusiveIDInput = ""
    @State private var isEditingExclusiveID = false
    @State private var accountEmail = ""
    @State private var canChangeExclusiveID = true
    @State private var profileVisibility: ProfileVisibility = ProfileSharingSettings.visibility

    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false
    @State private var showLogoutConfirmation = false
    @State private var showAuthSheet = false
    @State private var authSheetMode: AuthEntryMode = .signIn

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(L10n.t("account_section_account"))
                    accountPanel

                    sectionTitle(L10n.t("account_section_visibility"))
                    visibilityPanel

                    if sessionStore.isLoggedIn {
                        sectionTitle(L10n.t("account_section_actions"))
                        logoutPanel
                    }

                    if !sessionStore.isLoggedIn {
                        sectionTitle(L10n.t("account_section_developer"))
                        backendCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .task {
            await refreshMeIfPossible()
        }
        .alert("提示", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message)
        }
        .alert(L10n.t("settings_logout_confirm_title"), isPresented: $showLogoutConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("settings_logout"), role: .destructive) {
                sessionStore.logoutToGuest()
                accountEmail = ""
                exclusiveIDDraft = ""
                profileVisibility = ProfileSharingSettings.visibility
                toast(L10n.t("switched_to_guest_mode"))
                dismiss()
            }
        } message: {
            Text(L10n.t("settings_logout_confirm_message"))
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthEntryView(
                onContinueGuest: { showAuthSheet = false },
                initialMode: authSheetMode,
                onAuthenticated: {
                    Task { await refreshMeIfPossible() }
                    showAuthSheet = false
                }
            )
            .environmentObject(sessionStore)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                    Text(L10n.t("back"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(FigmaTheme.text)
                .appFullSurfaceTapTarget(.rectangle)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.t("account_center_title"))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(FigmaTheme.text)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(L10n.t("done"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
                    .appFullSurfaceTapTarget(.rectangle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 33 * 0.48, weight: .bold))
            .foregroundColor(FigmaTheme.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessionStore.isLoggedIn {
                Text(displayNameDraft.isEmpty ? L10n.t("explorer_fallback") : displayNameDraft)
                    .font(.system(size: 32 * 0.58, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                accountInfoRow(label: L10n.t("account_display_name_label"), value: displayNameDraft.isEmpty ? L10n.t("explorer_fallback") : displayNameDraft)
                accountInfoRow(label: L10n.t("account_exclusive_id_label"), value: exclusiveIDDraft.isEmpty ? "--" : exclusiveIDDraft)
                accountInfoRow(label: L10n.t("account_email_label"), value: accountEmail.isEmpty ? L10n.t("not_linked") : accountEmail)

                Divider().overlay(Color.black.opacity(0.08))

                if isEditingDisplayName {
                    TextField(L10n.t("settings_display_name_placeholder"), text: $displayNameInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .semibold))

                    HStack(spacing: 8) {
                        capsuleAction(L10n.t("account_save_display_name"), filled: true) {
                            Task { await updateDisplayName(to: displayNameInput) }
                        }
                        capsuleAction(L10n.t("cancel"), filled: false) {
                            isEditingDisplayName = false
                            displayNameInput = displayNameDraft
                        }
                    }
                } else {
                    capsuleAction(L10n.t("settings_edit_name_title"), filled: false) {
                        displayNameInput = displayNameDraft
                        isEditingDisplayName = true
                    }
                }

                if canChangeExclusiveID {
                    if isEditingExclusiveID {
                        TextField(L10n.t("account_exclusive_id_placeholder"), text: $exclusiveIDInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold))

                        Text(L10n.t("account_exclusive_id_change_once"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)

                        HStack(spacing: 8) {
                            capsuleAction(L10n.t("account_save_exclusive_id"), filled: true) {
                                Task { await updateExclusiveID(to: exclusiveIDInput) }
                            }
                            capsuleAction(L10n.t("cancel"), filled: false) {
                                isEditingExclusiveID = false
                                exclusiveIDInput = exclusiveIDDraft
                            }
                        }
                    } else {
                        capsuleAction(L10n.t("account_edit_exclusive_id"), filled: false) {
                            exclusiveIDInput = exclusiveIDDraft
                            isEditingExclusiveID = true
                        }
                    }
                } else {
                    Text(L10n.t("account_exclusive_id_locked"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                }

            } else {
                Text(L10n.t("guest_mode"))
                    .font(.system(size: 32 * 0.58, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Divider().overlay(Color.black.opacity(0.08))

                Text(L10n.t("please_sign_in_to_access_your_account"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                capsuleAction(L10n.t("account_login"), filled: true) {
                    authSheetMode = .signIn
                    showAuthSheet = true
                }
                capsuleAction(L10n.t("account_register"), filled: false) {
                    authSheetMode = .register
                    showAuthSheet = true
                }
            }
        }
        .cardStyle()
    }

    private func accountInfoRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private var visibilityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { profileVisibility != .private },
                set: { newValue in
                    let previousVisibility = profileVisibility
                    let newVisibility: ProfileVisibility = newValue ? .friendsOnly : .private
                    guard profileVisibility != newVisibility else { return }
                    profileVisibility = newVisibility
                    Task { await updateVisibility(previous: previousVisibility) }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("settings_profile_visibility_friends"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(profileVisibility == .private ? L10n.t("settings_profile_visibility_private") : L10n.t("settings_profile_visibility_friends"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }
            }
            .disabled(!sessionStore.isLoggedIn)
        }
        .cardStyle()
    }

    private var logoutPanel: some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: L10n.t("settings_logout"),
                subtitle: L10n.t("settings_logout_subtitle"),
                iconColor: .red.opacity(0.88),
                titleColor: .red.opacity(0.9),
                subtitleColor: .red.opacity(0.62)
            ) {
                showLogoutConfirmation = true
            }
        }
        .cardStyle()
    }

    private func infoRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = FigmaTheme.primary,
        titleColor: Color = FigmaTheme.text,
        subtitleColor: Color = FigmaTheme.subtext,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(titleColor)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(subtitleColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .appFullSurfaceTapTarget(.rectangle)
        }
        .buttonStyle(.plain)
    }

    private func capsuleAction(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(filled ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(filled ? FigmaTheme.primary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(filled ? 0 : 0.12), lineWidth: filled ? 0 : 2)
                )
                .appFullSurfaceTapTarget(.roundedRect(24))
        }
        .buttonStyle(.plain)
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("backend_configuration"))
                .font(.system(size: 13, weight: .semibold))

            TextField(L10n.t("backend_base_url_placeholder"), text: $backendBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button(L10n.t("save_backend_url")) {
                    BackendConfig.baseURLString = backendBaseURL
                    toast(L10n.t("backend_url_saved"))
                }
                .buttonStyle(.borderedProminent)
            }

            Text(String(format: L10n.t("backend_current_url_format"), BackendConfig.baseURLString.isEmpty ? L10n.t("not_linked") : BackendConfig.baseURLString))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .cardStyle()
    }

    private func refreshMeIfPossible() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            displayNameDraft = me.displayName
            exclusiveIDDraft = me.resolvedExclusiveID ?? ""
            displayNameInput = displayNameDraft
            exclusiveIDInput = exclusiveIDDraft
            isEditingDisplayName = false
            isEditingExclusiveID = false
            accountEmail = me.email ?? sessionStore.currentEmail ?? ""
            canChangeExclusiveID = me.canChangeExclusiveID
            if let pv = me.profileVisibility {
                profileVisibility = pv
                ProfileSharingSettings.visibility = pv
            }
        } catch {
            toast(String(format: L10n.t("account_fetch_profile_failed_format"), error.localizedDescription))
        }
    }

    private func updateDisplayName(to input: String) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return toast(L10n.t("profile_name_empty"))
        }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await BackendAPIClient.shared.updateDisplayName(token: token, displayName: value)
            displayNameDraft = value
            displayNameInput = value
            isEditingDisplayName = false
            toast(L10n.t("profile_name_updated"))
        } catch {
            toast(String(format: L10n.t("update_failed_format"), error.localizedDescription))
        }
    }

    private func updateExclusiveID(to input: String) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard canChangeExclusiveID else { return toast(L10n.t("account_exclusive_id_locked")) }

        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return toast(L10n.t("account_exclusive_id_empty")) }
        guard value.range(of: #"^[A-Za-z0-9_]{1,24}$"#, options: .regularExpression) != nil else {
            return toast(L10n.t("account_exclusive_id_rules"))
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await BackendAPIClient.shared.updateExclusiveID(token: token, exclusiveID: value)
            exclusiveIDDraft = updated.resolvedExclusiveID ?? value
            exclusiveIDInput = exclusiveIDDraft
            canChangeExclusiveID = updated.canChangeExclusiveID
            accountEmail = updated.email ?? sessionStore.currentEmail ?? accountEmail
            isEditingExclusiveID = false
            toast(L10n.t("account_exclusive_id_updated"))
        } catch {
            toast(String(format: L10n.t("update_failed_format"), error.localizedDescription))
        }
    }

    private func updateVisibility(previous: ProfileVisibility) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await BackendAPIClient.shared.updateProfileVisibility(token: token, visibility: profileVisibility)
            ProfileSharingSettings.visibility = profileVisibility
            toast(L10n.t("visibility_updated"))
        } catch {
            profileVisibility = previous
            toast(String(format: L10n.t("update_failed_format"), error.localizedDescription))
        }
    }

    private func toast(_ text: String) {
        message = text
        showMessage = true
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: FigmaTheme.softShadow, radius: 18, x: 0, y: 8)
    }
}
