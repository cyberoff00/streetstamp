# Single Email Password Identity Design

**Goal:** Add a one-off `email_password` auth identity for the existing `yinterestingy@gmail.com` account without changing or replacing any existing user data.

## Scope

- Apply a one-time data patch on the production server only.
- Do not change backend application code.
- Do not create a new user record.
- Do not overwrite journeys, friends, postcards, notifications, or other profile data.

## Approach

- Locate the existing user ID currently mapped by `emailIndex["yinterestingy@gmail.com"]`.
- Reuse that existing user record and its current `passwordHash`.
- Create a new `authIdentities` record with:
  - `provider: "email_password"`
  - `providerSubject: "yinterestingy@gmail.com"`
  - `email: "yinterestingy@gmail.com"`
  - `emailVerified: true`
  - `userID` pointing to the existing account
  - `passwordHash` copied from the current user record
- Leave `emailIndex` pointing at the same existing `userID`.

## Validation

- Back up the production data file before patching.
- Confirm the new `authIdentities` record exists and points to the original `userID`.
- Call `/v1/auth/forgot-password` for `yinterestingy@gmail.com`.
- Verify a password reset token is created.
- Verify the server can send the reset email through SES.
