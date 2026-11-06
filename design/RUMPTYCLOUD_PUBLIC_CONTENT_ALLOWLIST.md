# RumptyCloud static review site — public content allowlist

**Stage:** H1.1. No repository was created and nothing was deployed.

**Rule:**
- Treat the site as **public**. RumptyCloud documents no access protection for static sites.
- Only files on the allowlist may be copied into the separate review-site repository. Everything else is excluded by default.

## 1. Allowed (after a per-file review)

| Content | Source | Condition |
|---|---|---|
| Approved design previews (synthetic data only) | `test_visual/previews/goldens/*.png` | Rendered from test fixtures (fictional names such as "Funke Adeyemi"); no real user data |
| Approved-vs-implemented comparison sheets | `design/stage8_1_artisan_vs_approved/*.png` | Same fixtures |
| Visual-QA renders | `test_visual/goldens/**` (Stage 8, 8.1, 8.2) | Same fixtures; no internal paths in the images |
| Preview gallery page | `design/STAGE8_PREVIEW_GALLERY.html` | Only after removing links to non-allowlisted files |
| Public product description and release notes | Written for the site | Factual only; no security claims |

## 2. Excluded (never publish)

- **Security material:**
  - security reviews, audits and vulnerability findings: every `*SECURITY*`, `*AUDIT*` and `*READINESS*` report, all `STAGE8_*_REPORT.md`, `P0_REMEDIATION_PLAN.md`;
  - internal implementation reports and authorisation packages;
  - `firestore.rules`, `storage.rules`, `functions/` source.
- **Credentials and configuration:**
  - any credential or secret, including `.secret.local`, keystores and `key.properties`;
  - `google-services.json` and `firebase_options.dart`. The API keys in them are not secrets, but publishing project configuration has no benefit.
- **Personal, financial and production data:**
  - production data exports, screenshots of live data, identity documents, dispute evidence, payment or payout details;
  - anything under `functions/test` or `firestore-tests` (internal attack and abuse scenarios).
- **Source code.**

## 3. Process

1. A separate repository holds only copies of allowlisted files.
2. Before each push, a reviewer runs:
   - `git grep -nE "sk_(live|test)_|AIza|PRIVATE KEY|@gmail|password"` (must return nothing);
   - an image check against this list.
3. Pushes go to a protected branch only, with required review.
4. If something sensitive is published: remove it, redeploy, and treat it as exposed. Rotate any secret, and assume caches or crawlers kept a copy.
