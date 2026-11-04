# 08 — Messaging & Notifications

The last of the three independent tracks flagged as pending in `03-ia-navigation-journeys.md` §2. Closes the messaging/notification gaps in `01-ux-audit.md` §5, resolves the "Reports" deferral from `05-trust-score.md` §2.5, and formalizes the escrow-specific reminder triggers `06-escrow-wallet.md` §7 deferred to this doc's general mechanism.

---

## 1. What exists today, precisely

**Chat** (`lib/core/services/chat_service.dart`, read directly): a job's `messages` subcollection *is* the chat thread — no separate chat document exists, confirmed by the service's own code comment. Four message types (`MessageType`: `text, image, negotiation, system` — `message_model.dart:3`). Read receipts exist but are minimal: a per-message boolean `isRead`, settable only to `true` (`firestore.rules` restricts chat message `update` to the `isRead` field alone) — no "delivered vs. read" distinction, no read timestamp. `watchUnreadCount`/`unreadCount` both exist (live-stream and one-shot variants). **No typing indicator, no archive, no search** — confirmed absent, nothing in `ChatService` or the rules touches any of the three.

**Notifications** (`lib/core/services/notification_service.dart` + `firestore.rules:420-436`, read directly): a hard-coded whitelist of exactly **12** notification types is all the rules permit a non-admin client to create: `quote_received`, `quote_accepted`, `quote_rejected`, `quote_withdrawn`, `dispute_raised`, `review_received`, `job_assigned`, `job_status_update`, `appointment_scheduled`, `message_received`, `verification_approved`, `verification_rejected`. Every one of these is a **transactional** notification (something just happened) — **there is no reminder-class type in the whitelist at all**, and notably `dispute_raised` exists but there's no `dispute_resolved` — a customer/artisan isn't notified when their dispute is closed, only when one is opened.

---

## 2. Brief requirements vs. what's implemented

| Brief requirement | Status |
|---|---|
| Conversation list | ✅ `my_chats_screen.dart` |
| Attachments / Photos | ✅ `MessageType.image` |
| Voice notes (marked "future-ready" in the brief itself) | ❌ not built — correctly deferred per brief's own framing, see §3.5 for the forward-compatible groundwork |
| Read receipts | ⚠️ minimal — binary `isRead` only, no delivered-state, no timestamp |
| Typing indicators | ❌ absent |
| Archive | ❌ absent |
| Search | ❌ absent |
| Job-linked conversations | ✅ already true by construction — every thread *is* a job's subcollection |
| Complaint reporting from chat | ❌ absent — `03-ia-navigation-journeys.md` §3.3 already found the concrete gap (no arrow from Chat into the dispute flow) and proposed an interim fix; full design in §6 below |
| Push notifications | ✅ FCM, confirmed end-to-end in `01-ux-audit.md` §0 |
| In-app notifications | ✅ but only the 12 transactional types |
| Reminder notifications (escrow, appointment, arrival, review) | ❌ none exist — zero reminder-class types in the whitelist |
| Dispute updates | ⚠️ partial — raised only, not resolved |
| Verification updates | ✅ approved/rejected both present |
| Support replies | ❌ not in the whitelist — a resolved support ticket doesn't notify the user |
| Notification preferences | ❌ no preferences screen or per-type opt-out exists anywhere |

---

## 3. Chat redesign

### 3.1 Typing indicators
Lightweight, ephemeral, presence-style — not stored as chat history:
```
jobs/{jobId}/typing/{uid}   (doc per participant, not appended)
  isTyping: boolean
  updatedAt: Timestamp
```
Client writes on debounced keystroke events (e.g., set `true` on first keystroke, auto-clear via a client-side timer + a final `false` write on send/blur — no server TTL mechanism needed since the doc count is bounded to 2 participants per job, trivial to leave stale). Rules: write restricted to `isOwner(uid)` and job-party membership, same pattern as `liveLocation` in `07-gps-flow.md` §3. **Not swept into the message history** — this is presence, not content, and should never appear in `messagesStream`.

### 3.2 Read receipts — extend, don't overhaul
Current binary `isRead` is adequate for the common case; extend rather than replace:
- Add `readAt: Timestamp?` alongside `isRead` (rules already permit `readAt` in the same field-diff whitelist — confirmed at `firestore.rules:432-434`, so **this needs zero rules change**, only a model/service update).
- Distinguish delivered (message written, recipient hasn't opened the thread) from read (recipient opened the thread) only if there's real product demand for it — for a 1:1 job-scoped chat (not a messaging app with dozens of threads), the extra state is likely not worth the complexity. **Recommendation: skip delivered-state, ship `readAt` only.**

### 3.3 Archive
Per-user, not per-thread (a customer archiving a completed job's chat shouldn't affect the artisan's view of it):
```
users/{uid}/archivedChats/{jobId}   (doc = presence means archived)
  archivedAt: Timestamp
```
`/my-chats` filters out archived thread IDs by default, with an "Archived" filter tab to view them — cheap, standard pattern, no changes needed to the `messages` subcollection itself.

### 3.4 Search
Firestore has no native full-text search — a real engineering tradeoff to make explicitly rather than hand-wave:
- **MVP**: client-side search across already-loaded thread previews (`watchLastMessage` results) — searches conversation titles/last-message text only, not full message history. Zero new infrastructure, ships immediately.
- **Full message-content search**: requires a dedicated search index (Algolia, Typesense, or Firestore's own extension for it) synced via a Cloud Function on message write. Real ongoing cost (indexing service + sync function) for a feature whose actual usage frequency is unknown pre-launch. **Recommendation: ship the MVP client-side version now, revisit full-text search only if usage data post-launch shows people actually need to search old message content**, not preemptively.

### 3.5 Voice notes — forward-compatible groundwork only, per the brief's own "future-ready" framing
Not building playback UI now. What *is* worth doing now, cheaply: add `MessageType.voice` to the enum and reserve `voiceUrl`/`voiceDurationSeconds` fields on `MessageModel` (mirroring the existing `imageUrl` pattern), so a future implementation is additive rather than requiring a message-model migration. This is a 10-minute addition with real optionality value — flagged as a Phase 1.5-adjacent quick win, not its own project.

### 3.6 Complaint reporting from chat — full design (interim fix already shipped per `03-ia-navigation-journeys.md` §4)
`03`'s interim fix (a "Report an issue" action in `/chat/:jobId`'s app bar linking to the existing `/dispute/:jobId`) should already be live. This section is the richer version:
- Add a lightweight **report category** step before the existing dispute form (e.g., "No-show," "Unsafe behavior," "Payment issue," "Other") — categorization has two real uses: it lets `05-trust-score.md` §2.5's "Reports" concept exist as something distinct from a formal dispute (a report can be filed without necessarily escalating to a full dispute — see below), and it gives admin triage a head start.
- **Resolves `05-trust-score.md` §2.5's deferral**: a "report" is now concretely a lighter-weight action than a dispute — same UI entry point, but doesn't require the job to reach a specific status and doesn't trigger the full dispute state machine (`disputed` job status). Model as a new lightweight collection:
```
reports/{reportId}
  jobId: string
  reportedBy: string (uid)
  reportedAgainst: string (uid)
  category: string
  description: string
  evidenceUrls: string[]   // reuses StorageService.uploadDisputeEvidence's existing pattern/limits
  status: 'open' | 'reviewed' | 'dismissed'
  createdAt: Timestamp
```
- Feeds `05-trust-score.md`'s dispute-history term as a smaller-weight signal alongside `openDisputeCount` (a pattern of reports without formal disputes is still a real trust signal, just a weaker one) — exact weighting is `05`'s call to finalize once this exists, flagged there originally, now unblocked.

---

## 4. Notification taxonomy redesign

### 4.1 Extend the whitelist with reminder-class types
```
'dispute_resolved', 'support_reply',
'escrow_reminder', 'payout_blocked_reminder', 'material_payment_requested',   // from 06-escrow-wallet.md §7
'appointment_reminder', 'arrival_alert',                                      // new, tied to 07-gps-flow.md
'review_reminder', 'report_received'                                          // new
```
Straightforward `firestore.rules:425-430` whitelist extension — mechanically simple, the design work is in *when* each fires (below), not the rule change itself.

### 4.2 New reminder triggers, precisely specified
- **`escrow_reminder`** / **`payout_blocked_reminder`**: already fully specified in `06-escrow-wallet.md` §7 (24h/40h pre-auto-release, daily until a blocked payout resolves) — this doc just supplies the taxonomy slot.
- **`appointment_reminder`**: scheduled Cloud Function (same `onSchedule` pattern as `autoReleaseEscrow`), fires ~2h before `confirmedAppointment` (from `07-gps-flow.md`'s confirmed data model) to both parties.
- **`arrival_alert`**: fires once, triggered by `07-gps-flow.md` §2's arrival-confirmation event (step H) — "Your artisan has arrived" to the customer. Event-driven, not scheduled.
- **`review_reminder`**: scheduled function, queries jobs `status == 'completed'` with no matching `reviews` doc after e.g. 48h, single reminder (not repeated — avoid nagging), to the customer only.
- **`report_received`** (admin-facing): ties to §3.6's new `reports` collection — notifies the admin Trust & Safety queue (feeds into `05-trust-score.md` §4's anomaly surface, `10-admin-redesign.md`'s territory for the actual UI).

### 4.3 Support replies
`support_reply` fires when `SupportTicketService.resolveTicket` (confirmed to exist in `01-ux-audit.md` §0's recon) transitions a ticket — currently silent. Straightforward addition alongside the existing service, no new infrastructure.

---

## 5. Notification Preferences — new screen (full spec)

Confirmed absent everywhere in the codebase; the brief names this explicitly.

> **Implementation note (post-build correction):** what actually shipped is smaller than this spec, on purpose. Building the full push/in-app toggle-pair version below turned out to require either modifying live Cloud Functions (to make push suppression real) or shipping toggles that looked functional but silently did nothing — both rejected as dishonest UI. What shipped instead: `settings_screen.dart` exposes the single existing `UserModel.notificationsEnabled` boolean (already wired into `notification_provider.dart`'s `startForegroundListener` gating) as one real, fully-functional toggle — no per-category granularity, no push/in-app split, no `/settings/notifications` route (it's inline in the existing Settings screen). This spec's richer version remains the target if the per-category taxonomy and Cloud-Functions-side enforcement described in §4 ever get built — until then, treat this section as aspirational, not as-built.

- **Purpose**: let a user control which of the now-expanded notification set they receive, and through which channel (push vs. in-app-only), without silencing anything safety-critical.
- **User goal**: "Stop notifying me about X, but never let me miss Y."
- **Layout**: grouped list — **Transactional** (job status, quotes, messages — the original 12), **Reminders** (escrow, appointment, review — the new set from §4), **Account** (verification, support). Each row: label + a push/in-app toggle pair, not a single on/off (a user might want an in-app record without a push interruption, or vice versa).
- **Components**: standard themed switches (`AppTheme`'s existing chip/toggle styling, no new tokens needed), grouped under section headers matching the taxonomy above.
- **Interactions**: toggling writes immediately (no separate "Save" step — matches the existing `SettingsScreen`'s theme-toggle pattern, confirmed in `01-ux-audit.md` §0's recon as the app's established settings-UX convention, so this stays consistent with it).
- **Navigation**: new route under Settings (`/settings/notifications`), per `03-ia-navigation-journeys.md` §2's note that this was a low-risk, not-yet-spec'd addition — now spec'd, resolved.
- **Loading state**: preferences doc is small and cheap — no skeleton needed, a brief spinner on first load is sufficient.
- **Empty/default state**: every notification type defaults to **on** (push + in-app) — the burden should be on opting out, not opting in, for a trust/safety-relevant product; the one deliberate exception is §5.1 below.
- **Error state**: a failed toggle write should revert visibly (optimistic update rolled back), not silently fail leaving the UI showing a state that didn't actually save.
- **Success state**: instant visual toggle feedback is the success state — no separate confirmation needed for a settings screen.
- **Accessibility**: every switch needs an accessible label pairing the notification type name with its current state, not just a bare toggle control.
- **Animations**: standard switch animation only — this is a utility screen, not a place for the celebratory motion tier.
- **Firestore implications**: `users/{uid}.notificationPreferences: Map<String, {push: bool, inApp: bool}>` — a single map field on the existing user doc is sufficient (small, bounded key set), no new collection needed.
- **Security considerations**: owner-only read/write, same as every other user-profile field — no new rule pattern.

### 5.1 The one deliberate non-negotiable
**Dispute and account-suspension notifications should not be user-suppressible** — these are safety/due-process-relevant, not preference-relevant (a customer or artisan genuinely needs to know if a dispute was raised against them or their account was actioned, regardless of notification fatigue). Exclude `dispute_raised`, `dispute_resolved`, and any suspension-related type from the preferences screen entirely — always-on by design, not just by default.

---

## 6. What this doc deliberately isn't building

- Not designing a full messaging-app feature set (message reactions, threaded replies, @-mentions) — this is job-scoped 1:1 communication tied to a transaction, not a general chat product; matching the brief's actual scope, not exceeding it.
- Not building the `reports` collection's admin-facing triage UI — that's `10-admin-redesign.md`'s territory; this doc only defines the data model and notification hook.
- Not re-deriving the escrow-reminder timing logic — fully owned by `06-escrow-wallet.md` §7, cited not repeated.

---

**Next**: all three independent tracks (`06`, `07`, `08`) are now done — every placeholder in `03-ia-navigation-journeys.md` §2 is resolved. `09-screens-customer-artisan.md` (screen-by-screen redesign) is now unblocked and next in the recommended sequence, followed by `10-admin-redesign.md` and the closing `11-production-roadmap.md`.
