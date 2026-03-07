# Profile Notification And Level Layout Design

**Context**

The profile screen currently exposes social notifications as a standalone action tile, shows the level badge next to the nickname, and expands the invite card into multiple lines. The requested behavior is to simplify the top section, move level information into the progress row, and only surface the cloud notification affordance when notifications actually exist.

**Approved Design**

1. Sidebar header keeps only avatar, nickname, and subtitle. No level information is shown above the avatar.
2. Profile hero removes the level pill next to the nickname.
3. The progress row shows:
   - level badge on the far left
   - a narrower centered progress bar
   - a small question-mark button on the right
4. Tapping the question-mark button shows a lightweight bubble with the text `还差 X 段旅程升级`.
5. The standalone `互动通知` card is removed from the profile action list.
6. The sofa hero shows a cloud button in the top-left corner only when social notifications exist.
7. Tapping the cloud button opens the same notification sheet pattern already used in the friends page.
8. The invite card keeps a single-line `邀请好友` label.

**Implementation Notes**

- Reuse the existing notification sheet content structure from the profile/friends flow instead of introducing a new route.
- Keep notification unread badges on the cloud button when present.
- Extract any conditional presentation and copy into a small pure helper so the behavior is regression-testable.
