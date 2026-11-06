# HandyTrust — media security review (H1.2)

> **Superseded in part (5 November 2026):** see `RUMPTYCLOUD_MEDIA_MIGRATION_ROADMAP.md` for the recommendation in §3 (private media and dispute evidence are now long-term migration targets, each after its own security review and approval; identity documents stay excluded). The rest of this document still applies.

## 1. Today (Firebase Storage, verified in code)

- **Paths:**
  - `jobs/{jobId}/{uid}/[before|after/]image_n.jpg`: job, completion and chat images;
  - `profiles/{uid}/avatar.jpg`;
  - `users/{uid}/profile.jpg`: legacy writer `uploadProfilePhoto`, with no remaining callers;
  - `artisan_portfolio/{uid}/image_n.jpg`;
  - `verifications/{uid}/{selfie|id_front}.jpg`;
  - `disputes/{id}/{uid}/evidence_n.jpg`.
- **Rules:** image content type only, under 5 MB, owner or party write, admin read for sensitive paths (`storage.rules`).
- **Finding M1: download URLs are bearer tokens.** `getDownloadURL()` URLs are stored in Firestore (`imageUrls`, `selfieUrl`, `governmentIdUrl`, `evidenceImageUrls`, chat `imageUrl`…). Anyone holding a URL can read the file regardless of the Storage rules, until the token is revoked in the console. Access to "private" media therefore rests on keeping Firestore documents private, which the rules do.
- **Finding M2: avatar not deleted on account deletion.** `adminDeleteUser` deletes the `users/`, `verifications/` and `artisan_portfolio/` prefixes, but **not `profiles/{uid}/`**, where avatars are actually stored. Existing bug; needs a Functions change.
- **Finding M3:** predictable paths contain uids and job IDs. They aren't an access bypass (the rules check them), but they leak identifiers in URLs.

## 2. Threats in the proposed design and controls

| Threat | Control |
|---|---|
| Secret keys in the app | **None in the APK.** RumptyCloud keys are Functions secrets only; separate write, read and delete keys per bucket |
| Bucket-wide keys (no prefix scoping) | Presigned URLs bound to one key, Content-Type and ≤ 5-minute expiry; keys rotated quarterly and on staff change; revocation tested |
| Client-chosen paths / overwriting others' files | Server-generated UUID keys; one key per media record; no client key input; PUT URL valid for one key only |
| Unauthorised upload | Callable checks Auth plus Firestore role, job party and suspension (same as the rules); rate-limited per uid |
| Cross-user read of private media | Signed GET issued only after the relationship check; 5–15-minute TTL; nothing private in public buckets |
| Losing access (left job, suspended, admin removed) | No new URLs are issued after the relationship ends; issued URLs expire within the TTL. **Residual:** a URL already handed out works until expiry, so keep the TTL short |
| Public URL leakage | Public bucket only for already-public content; permanent URLs, so treat them as public forever |
| Malicious files (wrong type, oversized) | Content-Type bound in the signature; server HEAD check; reject and delete; image decode on the client before display |
| Permanent loss (no versioning) | Deletion only through the audited Functions job; delete key only in that job; a **separate backup copy** of private media (cost) or keep private media in Firebase |
| Vendor outage (single zone, no SLA) | Feature flag back to Firebase for new uploads; Firebase files remain |
| Compliance (NDPA 2023) | Data-protection assessment and DPA with the provider **before** any private personal data moves; sensitive media never moves |

## 3. Recommendation

- **Approve only public media** (avatars, portfolio) for RumptyCloud first.
- **Keep private media in Firebase Storage** until RumptyCloud documents encryption at rest and durability (or you accept the risk in writing) and a backup copy is in place.
- **Highly sensitive media stays in Firebase.**
- **Fix M2 independently** (Functions change).
