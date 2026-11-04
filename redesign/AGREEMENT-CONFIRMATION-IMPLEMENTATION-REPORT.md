# Agreement Confirmation Checkpoint — Implementation Report

Implements the "Negotiation Completed / Agreement Confirmation" lifecycle stage between quote acceptance and escrow payment.

## Design decision, stated up front

The brief's diagram shows new top-level statuses (`QUOTE_ACCEPTED`, `NEGOTIATING`, `AGREEMENT_PENDING`, `AGREEMENT_CONFIRMED`, `SCHEDULED`, `ESCROW_PAYMENT_REQUIRED`). Read literally, that would mean renaming/restructuring the existing `JobStatus` enum — a breaking change to every screen, every Firestore rule, every composite index, and every job document already in the database, and a direct contradiction of the brief's own instructions ("extend the existing architecture," "do not create duplicate systems," "use the project's existing naming conventions").

Instead: `agreementStatus` is implemented as a **fine-grained sub-state within the existing `JobStatus.inChat`**, using the exact same pattern the codebase already has for `JobProgressStage` (a sub-state within `JobStatus.inProgress`). `matched`, `inChat`, and `paymentPending` are unchanged. The brief's "SCHEDULED" step maps onto the already-existing `confirmedAppointment` field. This is what "extend, don't duplicate" means concretely here — reusing a pattern this codebase already trusts, not inventing a second one beside it.

---

## 1. Files changed

| File | Change |
|---|---|
| `lib/models/job_model.dart` | New `AgreementStatus` enum; 8 new fields on `JobModel`; `fromJson`/`toJson`/`copyWith` updated |
| `lib/models/audit_log_model.dart` | 3 new `JobActionType` values |
| `lib/core/services/job_service.dart` | 3 new pure validation predicates + 3 new transactional methods; `initPayment` rewritten to enforce the confirmation gate |
| `lib/providers/escrow_provider.dart` | `EscrowNotifier` gains a `NotificationService` dependency + 3 new methods |
| `firestore.rules` | 3 new field-scoped update rules; `agreedAmount` rule now locks after confirmation; `_isValidJobTransition` gates `inChat→paymentPending`; notification whitelist +3 types |
| `lib/screens/job/job_detail_screen.dart` | New `_AgreementSection` widget (5 render states); "Proceed to Payment" gated on confirmation (and made customer-only — a pre-existing gap, see §7) |
| `test/job_service_agreement_test.dart` | New — 24 unit tests (first test file in the project) |

No new files for models/services — everything extends an existing file, per the brief's instruction.

---

## 2. Database/schema changes

8 new fields on `jobs/{jobId}`, all optional/defaulted (safe for existing documents — see §7):

```
agreementStatus: 'negotiating' | 'pendingArtisanConfirmation' | 'confirmed' | 'changesRequested' | absent
agreementScope: string | absent
agreementConfirmedByCustomer: boolean (default false)
agreementConfirmedByArtisan: boolean (default false)
agreementCustomerConfirmedAt: Timestamp | absent
agreementArtisanConfirmedAt: Timestamp | absent
agreementChangesRequestedReason: string | absent
agreementUpdatedAt: Timestamp | absent
```

Reused, not duplicated: `agreedAmount` (locked price — same field negotiation already uses), `confirmedAppointment` (locked schedule — already exists), `customerAddress`/`customerLat`/`customerLng` (location, shown on the artisan's review card). No new collection, no new composite index — `agreementStatus` is read as part of the existing single-document `jobStreamProvider` listener, not a new query.

---

## 3. State machine changes

**No change to `JobService.allowedTransitions`** — `matched→inChat→paymentPending` is exactly as before. What's new is a business-rule *gate* on top of one already-valid transition:

```
inChat ──(customer confirms)──► agreementStatus: pendingArtisanConfirmation
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    ▼                                             ▼
        (artisan accepts)                          (artisan requests changes)
   agreementStatus: confirmed                   agreementStatus: changesRequested
                    │                                             │
                    ▼                                             │
   inChat → paymentPending now permitted          back to the top — customer
   (previously permitted any time inChat)          can revise and re-confirm
```

`JobService.initPayment` — previously a one-line delegate to the generic `updateJobStatus` — is now its own transaction (mirroring how `updateAgreedAmount` already does this for its own extra business rule), so it can check `agreementStatus == confirmed` before allowing the transition. The check lives in `JobService.canInitPayment`, a pure static predicate — same function is called by the real transaction and by the unit tests.

---

## 4. UI changes

New `_AgreementSection` in `job_detail_screen.dart`, rendered inline (matching the existing `_AppointmentSection` pattern — no new route). Five states:

1. **Customer, not yet confirmed** — editable scope/price summary + "Confirm Agreement." If re-entering after `changesRequested`, the artisan's reason is shown inline above the form.
2. **Customer, pending artisan** — "Waiting for the artisan to confirm the agreement," spinner, no action available (cannot start payment from here).
3. **Artisan, review pending** — read-only card (service, description, agreed price, schedule, location) + **Accept Agreement** / **Request Changes**.
4. **Either party, confirmed** — locked, read-only summary ("Agreement Confirmed," green check).
5. **Artisan, not yet the artisan's turn** — nothing rendered; they act via chat until the customer confirms.

"Request Changes" opens a free-text reason dialog, styled identically to the existing `showCancellationReasonDialog` (same `AlertDialog` shape/radius/typography/`context.colors` usage) but as its own function — that dialog's title/buttons/preset reasons are cancellation-specific and would have been semantically wrong to repurpose. No new design tokens, no new component library — borderless `context.colors.surfaceVariant` cards, existing themed buttons, existing `error_snackbar.dart` for failures.

**Incidental fix**: "Proceed to Payment" previously had no `isCustomer` check at all (the artisan could see it too). Fixed in the same edit, since I was already gating this exact button on the new confirmation requirement.

---

## 5. Security rule changes

Three new field-scoped `allow update` rules on `jobs/{jobId}`, each restricted to exactly the fields that action should touch:

- **Customer confirms**: writable only from `negotiating`/`changesRequested`/absent; can never write `agreementConfirmedByArtisan` or `agreementArtisanConfirmedAt` (satisfies "customer cannot update artisan confirmation").
- **Artisan accepts**: writable only from `pendingArtisanConfirmation`; can never write `agreementConfirmedByCustomer` or `agreementCustomerConfirmedAt` (satisfies "artisan cannot update customer confirmation").
- **Artisan requests changes**: same actor/state restriction; only resets the artisan's *own* flag, never touches the customer's fields.

All three inherit the existing `resource.data.artisanId == request.auth.uid` check already used everywhere else in the ruleset — this is what makes "artisan cannot accept an agreement they were not selected for" true: `artisanId` is set once, at quote-acceptance time, and nothing in this feature can reassign it.

**Locking after confirmation**: the pre-existing `agreedAmount` negotiation rule gained one more condition — `resource.data.get('agreementStatus', 'negotiating') != 'confirmed'`. **Payment gating**: `_isValidJobTransition`'s `inChat→paymentPending` branch gained `job.get('agreementStatus', 'negotiating') == 'confirmed'`.

Every reference to the new field in rules uses `.get(path, 'negotiating')`, never bare dot-access — direct `resource.data.agreementStatus` access would throw a rules-evaluation error on any job document that predates this field, which is every job in the database today. This is the mechanism that makes the migration story in §7 work at all.

**Auditability**: free — every write goes through `JobService`'s existing transactional pattern, which writes an immutable `auditLogs` entry in the same commit as every other job mutation. No separate audit work was needed.

---

## 6. Tests added

`test/job_service_agreement_test.dart` — 24 tests, all passing (verified by actually running `flutter test`, not just `flutter analyze`). **This is the first test file in the project** — worth knowing, since it means the test-running toolchain itself (not just this feature) is now confirmed to work.

Scope, precisely: these test the three pure predicates (`canConfirmAgreement`, `canRespondToAgreement`, `canInitPayment`) directly — the same functions the real transactional methods call, not a re-implementation. Every scenario from the brief is covered (customer confirms without an accepted quote, artisan accepts another artisan's agreement, payment before confirmation, plus the full valid-path set) except one:

**Not covered, and I want to be direct about why**: "modifying locked terms after confirmation" is fundamentally enforced by `firestore.rules`, not by Dart logic — the true test for it is a Firestore rules-unit test (`@firebase/rules-unit-testing`, a Node.js tool running against the Firebase emulator). **This repo has no emulator configuration and no rules-testing setup at all** — confirmed absent when I checked `firebase.json` earlier in this program, and still absent now. Building that harness from scratch is a real, separate piece of infrastructure work, not something to bolt on silently inside this feature's scope. I tested the closest Dart-side proxy instead (`canConfirmAgreement` correctly returns `false` once `agreementStatus == confirmed`, preventing the *client* from attempting the write) and am flagging the rules-layer gap explicitly rather than claiming coverage that isn't real.

---

## 7. Migration considerations

- **Every field is optional/defaulted** — existing job documents need no backfill. `agreementStatus` absent is read as `negotiating` everywhere (Dart's `?? AgreementStatus.negotiating`, rules' `.get(path, 'negotiating')`).
- **Real behavior change for jobs already sitting at `inChat` when this ships**: any in-flight negotiation today has no `agreementStatus`, which resolves to `negotiating` — meaning **they will be blocked from proceeding to payment** until they go through the new confirm/accept flow, even if they'd already informally agreed via chat under the old system. This is a deliberate consequence of the brief's own hard rule ("payment cannot begin unless agreementStatus == confirmed," no exception carved out) — flagged clearly rather than silently shipped, since it's the one change with real user-facing impact on already-in-progress jobs, not just new ones.
- **No index deployment needed** — unlike the last feature I shipped (Wallet), this one touches no new queries, only an existing single-document listener.
- **Rules deployment required**: `firestore.rules` changes need `firebase deploy --only firestore:rules` to take effect — I cannot run this from here; same constraint as the earlier Firestore-index gap, flagged the same way.
- **Recommended follow-up, not done here**: a Firestore emulator + rules-unit-testing setup would close the one real test gap in §6, and would benefit every rules change this program makes from now on, not just this feature.
