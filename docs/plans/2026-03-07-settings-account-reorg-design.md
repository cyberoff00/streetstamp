# Settings Account Reorg Design

**Goal:** Move logged-in account controls into the account detail page, add a clear entry affordance on the account card, and localize the remaining single-line settings rows.

**Scope:**
- Make the logged-in account card navigable from Settings.
- Remove profile visibility and logout from the Settings root account section.
- Keep profile visibility and logout inside `AccountCenterView`, with logout confirmed before execution.
- Change the logged-in nickname display on the root card from bold to regular emphasis.
- Localize the profile visibility and map dark mode labels.
- Vertically center single-line toggle rows so they match the other settings list items.

**Non-goals:**
- No change-password entry in this pass.
- No backend auth flow changes.

**Validation:**
- Update presentation tests for account card and row copy.
- Run the affected `StreetStampsTests` cases plus a simulator build/test pass for the project target.
