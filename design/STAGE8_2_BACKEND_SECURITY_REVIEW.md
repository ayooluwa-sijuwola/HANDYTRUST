# Stage 8.2 — backend notification security review

**Dates:** first written 5 November 2026; **revised 6 November 2026** after the A1 corrections. The F-numbers refer to `STAGE8_2_NOTIFICATION_FINAL_CODE_REVIEW.md`.

**Status:** everything below was verified on the local emulators with unit tests. Nothing is deployed, and nothing has been tried on a real device.

## Threats

| # | Threat | Before | After (emulator-verified) | Residual risk |
|---|---|---|---|---|
| S1 | Sender fakes "read" or resets read state | Sender or receiver could set `isRead` to any value | Recipient only; false → true once; `readAt` server time | None known |
| S2 | Fake "delivered" | No delivered state | Recipient only; once; server time; only from server-confirmed snapshots (F-3) | A modified client of the **recipient** could stamp delivery without displaying the message. This only affects the recipient's own receipts |
| S3 | Opening one chat clears another's unread state | Client marked by receiver only | Client scopes by sender as well; rules allow receipts only on the reader's own incoming messages | None known |
| S4 | Push sent to a user who opted out | Only foreground suppression | Server checks `notificationsEnabled` | A user who disables it on an old app version still gets pushes until the server change is deployed |
| S5 | Previous account's pushes on a shared or signed-out phone | Single token, never removed | See below | See below |
| S6 | Someone registers another person's FCM token under their own account (F-11) | n/a | See below | See below |
| S7 | Lock-screen exposure | Message text, amounts and free text in push bodies | **No stored body is ever pushed:** fixed reviewed body per type; fixed server titles; generic titles for message, dispute and payout (F-9). Android `visibility: private` | `visibility: private` hides text only on a secure lock screen with "hide sensitive content" on, and iOS follows *Show Previews*. Titles such as "New Quote Received" are visible, but contain no amounts or names |
| S8 | Valid tokens deleted on transient errors | n/a | Only two FCM error codes delete, by compare-and-delete. The ownership release (F-7) and pruning (F-8) are compare-and-delete too | None known |
| S9 | Token data exposure | `fcm_tokens` unreadable | Same; devices unreadable; logs carry counts, not tokens | — |
| S10 | Unlimited registrations: storage, fan-out, cost (F-8) | n/a | See below | See below |
| S11 | Unauthorised route in payload | Client allow-list | Server routes only `/job/`, `/notifications` and so on; the client builds `/chat/` only from IDs matching `[A-Za-z0-9_-]{1,128}`; allow-list unchanged | None |
| S12 | Receipt listeners from the previous account keep running under the next (F-4) | Not auto-disposed | Auto-disposed; cancelled when the root stops watching at sign-out | Riverpod 2.6.1 cancels only a source stream that has emitted. Firestore listeners emit at once (cache first), so the practical effect is none. The conversation-list providers are not auto-disposed (existing pattern); their queries fail permission checks under another account and stop, with no data exposure |
| S13 | Endless retry of refused receipt writes (F-10) | Immediate retry on every rollback | Back-off of 60 s, doubling to 30 min; batches ≤ 450 writes | None known |

### S5: previous account's pushes on a shared or signed-out phone

**After (emulator-verified):**
- The pre-sign-out hook removes the device registration and invalidates the token, capped at 8 s (F-5).
- A failed invalidation is **retried while signed out**, at start and on reconnect (F-6).
- The newest registration owns the token, ordered and atomic (F-7).
- Foreground pushes for any other account are hidden.

**Residual risk:** while a retry is pending (offline), **background or terminated** pushes for the old account are still shown by the OS. Their text is now generic (F-9). The risk ends when the device reconnects, or when another account registers.

### S6: someone registers another person's FCM token under their own account (F-11)

**After (emulator-verified):** reading a token needs access to the victim's device, since tokens aren't readable from Firestore. If a token is obtained:
- the thief's own pushes can no longer carry text they control (F-9);
- the victim's app hides foreground pushes not addressed to the victim;
- the victim's next app start re-registers, and the newest registration wins (F-7).

**Residual risk, unresolved (documented, not fixed):**
- **Background** pushes to the thief's account still appear on the victim's phone, with fixed titles and generic bodies.
- A thief who keeps re-registering the token can repeatedly take the victim's pushes away.

A full fix needs either:
- **App Check enforcement**, so only genuine app instances can register; or
- **data-only messages rendered by the app**, which can then check the recipient in the background too.

Both are outside A1. App Check has its own plan (`HANDYTRUST_FIREBASE_APP_CHECK_PLAN.md`).

### S10: unlimited registrations, storage, fan-out and cost (F-8)

**After (emulator-verified):**
- Device IDs must be UUIDs.
- Sends go to the 10 newest registrations; older ones are pruned on each registration.
- Sends go out in groups of up to 500.
- Registrations unrefreshed for 270 days are swept daily.

**Residual risk:**
- Each registration write still runs one Function invocation, and a user can loop writes against their own account. That is cost only. App Check would limit it.
- Whether FCM returns `invalid-argument` for a malformed token is unverified. Such tokens are kept as transient, but they're now bounded by the cap and the sweep.

## Conclusion

The changes reduce real risks (S1, S4, S5, S7, S10, S12, S13) without widening access.
- No change to Auth, payments, escrow, payouts or Paystack.
- No change to rules for other collections.

The F-11 residual risk is documented as unresolved, pending App Check or data-only messages.

## Before deployment

- Deploy to a non-production project first, in order: indexes → rules → Functions; release the app last.
- Verify on two physical devices:
  - multi-device delivery;
  - account switch;
  - offline sign-out, then reconnect;
  - lock-screen settings;
  - a pre-8.2 build tapping a message push.
- Watch the `push_result` and `device_sweep` logs for unexpected removals.
