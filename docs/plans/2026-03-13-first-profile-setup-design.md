# First Profile Setup Design

**Problem**

StreetStamps currently lets newly created users enter the app without completing a distinct first-time identity setup. Email registration and first-time Apple sign-in go straight into the authenticated experience, and display names are not globally unique. Existing backend data also contains duplicate display names.

**Goals**

- Show a one-time profile setup screen immediately after a brand new email registration or the first Apple sign-in that creates an app account.
- Keep the UI aligned with the current StreetStamps visual language by reusing the existing auth and equipment styling.
- Require a nickname before completion and enforce global uniqueness.
- Normalize historical duplicate nicknames by suffixing later duplicates with incrementing numbers.

**Non-goals**

- Do not block returning users who have already completed account setup.
- Do not redesign the general profile or settings editing flows beyond the nickname uniqueness rule.
- Do not introduce a separate avatar persistence model if current loadout storage can be reused.

**User Experience**

After a successful account creation event, the backend returns an auth payload flag indicating that the user still needs first-time profile setup. The iOS app stores the authenticated session as usual, but instead of dropping the user into the main tab flow it presents a full-screen setup view.

The setup view uses the same `FigmaTheme`, rounded card shapes, grid background, and avatar rendering already used in the app. The top section contains a title, short helper copy, nickname input, and current avatar preview. The lower section reuses the current equipment/loadout selection experience in a simplified embedded form so users can pick their look without feeling like they left the app’s design system. A single primary CTA saves both nickname and loadout, marks setup complete, and then dismisses into the main experience.

This screen appears only once per newly created account:

- Email registration: only after the registration flow creates a new app account and the user is successfully authenticated.
- Apple sign-in: only when the backend creates a new user for the Apple identity.
- Returning sign-ins: never shown again once `profileSetupCompleted` is true.

**Backend Design**

Each user record gains:

- `profileSetupCompleted: boolean`

The auth responses for email login/register and Apple login include:

- `needsProfileSetup: boolean`

For a newly created account:

- `profileSetupCompleted` starts as `false`
- `needsProfileSetup` returns `true`

For existing accounts:

- `profileSetupCompleted` remains `true` or its migrated value
- `needsProfileSetup` returns `false`

Display names become globally unique. The backend keeps `normalizeDisplayName`, but now checks uniqueness before accepting an update. Duplicate updates return `409`.

Historical normalization runs during database load/startup. For each normalized display name, the first user keeps the base value. Later users with the same normalized value are renamed to `Name2`, `Name3`, and so on, skipping any already-used suffixed values until a free one is found. This keeps migration deterministic and prevents future collisions with already suffixed names.

To let the iOS app save the setup in one request, the backend adds a dedicated endpoint:

- `POST /v1/profile/setup`

Payload:

- `displayName`
- `loadout`

Behavior:

- Validates auth
- Rejects invalid or duplicate display names
- Validates and normalizes loadout
- Persists both values
- Sets `profileSetupCompleted = true`
- Returns the updated profile DTO

Existing `PATCH /v1/profile/display-name` should also enforce uniqueness for later edits in settings/profile screens.

**iOS Design**

`BackendAuthResponse` and `UserSessionStore` gain awareness of `needsProfileSetup`. The session still becomes authenticated immediately so existing token-based services continue working, but app flow holds the user on a setup sheet until completion.

A lightweight local first-setup state is stored per user in `UserScopedProfileStateStore` so the app can resume gracefully if the screen is interrupted after auth but before completion. This local state is advisory; the source of truth remains backend `profileSetupCompleted`.

New view responsibilities:

- `FirstProfileSetupView`: one-time screen combining nickname capture and avatar setup
- Reuse `RobotRendererView`, `AvatarLoadoutStore`, `AvatarCatalogStore`, and `FigmaTheme`
- Reuse as much `EquipmentView` interaction logic as practical without changing the established visual direction

The authenticated handoff from `AuthEntryView` becomes:

1. Complete register/login request
2. Apply auth into `UserSessionStore`
3. If `needsProfileSetup == true`, present `FirstProfileSetupView`
4. On successful submit, update local `displayName` and `loadout`, clear pending setup marker, enter main UI

Returning users skip steps 3 and 4.

**Data Migration**

Startup migration touches backend persisted data only:

- Add missing `profileSetupCompleted`
- Default existing users to `true`
- Normalize duplicate historical display names to numbered suffix variants

This ensures current users are not forced through the setup screen retroactively.

**Testing Strategy**

Backend:

- Registration returns `needsProfileSetup: true` for new users
- First Apple-created account returns `needsProfileSetup: true`
- Existing Apple sign-ins return `needsProfileSetup: false`
- `POST /v1/profile/setup` rejects duplicate nicknames
- `PATCH /v1/profile/display-name` rejects duplicate nicknames
- Migration renames duplicates deterministically (`Name`, `Name2`, `Name3`)

iOS:

- `UserSessionStore.applyAuth` preserves `needsProfileSetup`
- Auth flow presents setup only for new users
- Completing setup updates local display name/loadout and clears pending state
- Existing users still enter the app directly

**Risks**

- Reusing too much of `EquipmentView` directly could make the first-time screen feel heavy; prefer extracting shared loadout controls if embedding the full screen is awkward.
- Historical nickname migration must be deterministic to avoid noisy test fixtures and unstable snapshots.
- The app must not accidentally show the setup screen for old accounts whose backend data predates the new field.
