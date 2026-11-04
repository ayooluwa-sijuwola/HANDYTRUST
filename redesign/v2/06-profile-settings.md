# V2 — Profile & Settings

Sixth/seventh screens, covered together per the pacing plan ("lower complexity, faster to spec"). Read both `profile_screen.dart` and `settings_screen.dart` in full for this doc — Settings turned out to be more complete and correctly-wired than expected; Profile has three real, verified navigation bugs worth fixing regardless of the visual reset.

**Evidence key**: 🟡 Extrapolated · 🔵 Inferred · 🟠 real bug found reading the current code, not a visual issue.

---

## 🟠 Real bugs found — fix these regardless of restyling

Confirmed directly in `profile_screen.dart`/`settings_screen.dart`, not inferred:

1. **Profile's "My Reviews" menu item routes to `/notifications`** (`profile_screen.dart` line 91) — opens the notification inbox, not anything review-related. There is no dedicated "my reviews" screen anywhere in the app today (reviews only render per-artisan-profile, never aggregated for "reviews I've received" or "reviews I've left"). **Fix**: either build a minimal My Reviews screen (artisan: reviews received; customer: reviews left) — genuinely in-scope since Reviews is an explicit brief module — or remove the menu item until one exists. A dead-wrong destination is worse than no entry at all; recommend building the minimal version rather than removing, since it's a small screen (a filtered `review_tile.dart` list, already exists as a component).
2. **Profile's "Payment Methods" routes to `/jobs`** (line 107) — clearly a copy/paste artifact, opens the jobs list. **Fix**: now that Wallet is a primary nav tab (`02-design-system-v2.md` §9.4), this menu item is redundant with a destination that already has its own top-level home — **remove it from Profile's menu entirely** rather than just fixing its target, to avoid two entry points to the same place fragmenting the IA.
3. **Profile's "About HandyTrust" is a no-op** (`onTap: () {}`, line 127) — does nothing at all. **Fix**: wire to a real (simple) about/legal screen — app version, terms of service, privacy policy links. Low effort, currently just dead.
4. **Settings' "Push Notifications" routes to `/notifications`** (line 130) — same misrouting pattern as bug #1, opens the inbox instead of preferences. This is the concrete, findable instance of the gap `08-messaging-notifications.md` §5 already designed a fix for (`/settings/notifications`, the full preferences screen) — that screen doesn't exist yet, so this button currently points at the wrong existing screen instead of the right nonexistent one. **Fix**: build `08` §5's spec and repoint this button to it — already fully designed, just needs building and wiring.

None of these four are visual-reset concerns — they'd need fixing even if this program had never touched colors or layout at all.

---

## Profile

### What's already right (keep, restyle only)
Role-aware header (artisan vs. customer variant), grouped menu sections, sign-out confirmation dialog, notification badge on the Notifications menu item — all sound patterns, just due for the v2 borderless-card visual language.

### Layout
1. **Page header** 🟡 — "Profile" title + settings-gear shortcut (kept — a direct settings shortcut from Profile is a reasonable, common pattern, no reason to remove it just because Settings is also reachable via the menu below).
2. **Profile header card** — role-aware (artisan: stats-forward; customer: name/email/location), navy-adjacent trust element if the user is a verified artisan (🟡 — reusing the Trust Score tier badge from `v2/02-artisan-profile.md` here too, so an artisan sees their own trust standing on their own profile, not just customers seeing it on others).
3. **Menu groups**, restyled to borderless gray-fill rows, corrected per the bug list above:
   - Group 1: My Jobs (→ `/jobs`, kept — a reasonable shortcut even with the My Tasks nav tab existing, same non-issue reasoning as most apps having both a nav tab and a profile shortcut to the same place), My Chats, **My Reviews (🟠 fixed — real destination)**.
   - Group 2: Notifications (badge kept), ~~Payment Methods~~ (🟠 removed), Settings.
   - Group 3: Help & Support, **About HandyTrust (🟠 fixed — real destination)**.
   - Group 4: Sign Out.

### Interactions, states
Unchanged from current behavior except the three fixed destinations above. Loading/error states already reasonable in the current code (skeleton header, graceful `SizedBox()` on error) — restyle only.

### Accessibility
Menu item icons need to stay paired with text labels (already true) — no color-only signaling risk on this screen, since it's mostly neutral-colored list rows plus the one red Sign Out item, which is a legitimate destructive-action use of red per `02-design-system.md` §6.1's destructive-button-variant guidance.

### Firestore / Security
Unchanged — reads the current user's own profile only, already correctly scoped.

---

## Settings

### What's already right (keep, restyle only)
This screen is in better shape than Profile — Account (username/name/email/password editing), Role & Status (mode switch, verification link), Appearance (a **real, working** dark-mode toggle), an Artisan-only group (Payout Details → bank details, Business Profile, Portfolio — all correctly wired), Support, About, and Account Actions (sign out, delete account) are all sound and correctly routed except the one bug above.

### Layout
Same section structure, restyled to the v2 language (bordered `_SettingsGroup` cards → borderless gray-fill), one content fix:
- **Notifications section**: replace the single mis-wired "Push Notifications → `/notifications`" row with `08-messaging-notifications.md` §5's actual preferences screen (grouped Transactional/Reminders/Account toggles) — this section goes from one broken stub to the fully-specified screen that was already designed and waiting to be built.

### Accessibility
The dark-mode toggle already has proper on/off sublabel text (not color-only) — good existing pattern, keep. Every `_SettingsItem` row already pairs an icon with a label — no change needed.

### Firestore / Cloud Function / Security
Unchanged — all existing settings actions (username/name/email/password edits, role switch, verification, bank details, business profile, portfolio, account deletion) already route to their correct, previously-specified destinations and services; this doc doesn't change any of that logic, only the visual skin and the one Notifications-section content fix above.

---

## Decision log
- **Removed "Payment Methods" from Profile's menu** rather than just fixing its destination — Wallet's new nav-tab status makes a second entry point to the same content pure IA redundancy, not a genuine shortcut (unlike "My Jobs," which duplicates a nav tab too but is a much more frequently-needed shortcut worth the redundancy — a judgment call, not a rule, but stated so it's clear why one duplicate stayed and the other didn't).
