# Password Reset Deep Link Design

**Goal:** Make password reset emails open the StreetStamps app directly with a usable reset token, then let the user submit a new password inside the app.

## Context

The current backend password reset flow generates a link and emails it successfully, but the link is not usable end-to-end:

- The backend emails `/reset-password?token=...` links.
- The backend exposes `POST /v1/auth/reset-password` but does not expose a browser page for `GET /reset-password`.
- The iOS app does not parse password reset links or present a reset-password form from incoming URLs.

As a result, users can receive password reset mail but cannot complete the flow by opening the emailed link.

## Chosen Approach

Use a custom app URL scheme:

- Email links become `streetstamps://reset-password?token=...`
- The iOS app handles the URL with existing `.onOpenURL` and web-browsing continuation hooks.
- The app stores the pending reset token in app-level deep-link state.
- The auth entry flow presents a password reset form when a valid reset token is pending.
- Submitting the form calls the existing backend endpoint `POST /v1/auth/reset-password`.

## Alternatives Considered

### 1. Custom App Scheme

Use `streetstamps://reset-password?token=...`.

Pros:

- Smallest change set
- Reuses existing backend reset endpoint
- No web page required
- Fastest path to a working user flow

Cons:

- Depends on the app being installed
- Less flexible than Universal Links for cross-device flows

### 2. HTTPS Link with Universal Link Handling

Use `https://.../reset-password?token=...` and let iOS claim the link.

Pros:

- Better long-term compatibility
- Works better with mixed web/app journeys

Cons:

- Requires associated domains and server-side hosting details
- Larger surface area and slower to ship

### 3. HTTPS Landing Page that Redirects to App

Use a web page as the entrypoint, then hand off to the app.

Pros:

- Best fallback story

Cons:

- Requires building and operating a web reset UI
- Unnecessary for the immediate bug fix

## Architecture

### Backend

- Keep token issuance and validation behavior unchanged.
- Change outbound password reset email links to the custom app scheme.
- Preserve existing token query parameter name `token`.

This keeps the contract simple: email content changes, reset semantics do not.

### iOS Deep-Link Routing

- Extend `AppDeepLinkStore` to parse `streetstamps://reset-password?token=...`.
- Store a pending password-reset intent with the token.
- Mark the URL as handled so the app can surface the auth flow.

### Auth UX

- Extend the auth entry experience to detect a pending reset token.
- Present a dedicated reset-password view inside the auth flow.
- Require the user to enter a new password and confirm it.
- Submit the token and new password to the backend.
- On success, show a clear completion message and return the user to sign-in.

### Error Handling

The app should translate backend failures into user-facing copy:

- `invalid token`
- `token expired`
- `token already used`
- password strength validation failure

If the URL is missing a token, the app should ignore it and not enter reset mode.

## Data Flow

1. User taps password reset in the app.
2. App calls `POST /v1/auth/forgot-password`.
3. Backend generates token and emails `streetstamps://reset-password?token=...`.
4. User taps the link.
5. iOS launches StreetStamps via custom URL scheme.
6. `StreetStampsApp` forwards the URL to `AppDeepLinkStore`.
7. `AppDeepLinkStore` stores the pending reset token.
8. Auth UI observes the pending token and presents the reset form.
9. User submits new password.
10. App calls `POST /v1/auth/reset-password` with `{ token, newPassword }`.
11. Backend updates password, invalidates sessions, and returns success.
12. App clears the pending reset token and returns to the sign-in state.

## Testing Strategy

### Backend

- Update password reset contract coverage to assert the outbound email uses `streetstamps://reset-password?token=...`.

### iOS

- Add unit tests for deep-link parsing:
  - parses valid reset token URLs
  - ignores reset URLs with empty tokens
- Add UI/state tests where practical for auth presentation logic:
  - pending reset token triggers reset mode
  - consuming the token clears pending reset state

## Scope Boundaries

In scope:

- App-scheme password reset links
- In-app reset-password UI
- Existing backend reset endpoint integration

Out of scope:

- Universal Links
- Web fallback pages
- Cross-device fallback experiences
