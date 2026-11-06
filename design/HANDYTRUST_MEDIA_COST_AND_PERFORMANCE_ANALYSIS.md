# HandyTrust — media cost and performance analysis (H1.2)

## 1. Verified prices (5 November 2026)

| | Firebase Storage (bucket `handytrust.firebasestorage.app`) | RumptyCloud buckets |
|---|---|---|
| Free storage | 5 GB-months (Blaze; only for buckets in us-central1 / us-west1 / us-east1) | 10 GB |
| Storage beyond free | Google Cloud Storage published rates (not captured in this audit) | **$0.02 / GB-month** |
| Free download | 100 GB / month (same regional condition) | In-network egress free; **internet egress price not documented** |
| Operations | 5K uploads + 50K downloads / month free, then GCS rates | Not documented |
| Billing | Postpaid Blaze, budget alerts available | **Prepaid credit, no spend alerts** |

The `handytrust` bucket location is **not recorded in the repo**. If it isn't one of the three US regions, the Firebase free quotas don't apply. Check the console.

## 2. Scenarios (assumptions stated; illustrative)

**Assumptions:**
- Images are compressed on the client (about 300 KB).
- Each job has 8 photos (customer, before and after).
- Each chat image is about 300 KB.
- Each stored image is viewed about 15 times.

| Scenario | New media / month | Stored after 12 months | Egress / month | Firebase est. | RumptyCloud est. |
|---|---|---|---|---|---|
| A: today's scale (≈ 300 jobs/month, ≈ 1,000 chat images) | ≈ 1 GB | ≈ 12 GB | ≈ 15 GB | Inside free quotas if US-region bucket: **≈ $0–1/month** | Storage ≈ $0.04; egress **unknown**; plus signing callables (Functions, existing) |
| B: 10× growth | ≈ 10 GB | ≈ 120 GB | ≈ 150 GB | Storage above free tier at GCS rates (≈ $2–3/month) plus egress above 100 GB at GCS rates | Storage ≈ $2.20/month; egress **unknown** |
| C: video added (≈ 300 clips × 30 MB / month) | +9 GB | +108 GB | +several hundred GB | Egress-dominated (GCS internet egress rates) | Storage ≈ $2/month; egress **unknown** — may dominate |

## 3. Conclusions

- **At current volumes the saving is negligible** (a few dollars a month at most), and RumptyCloud adds operating cost: signing functions, monitoring, a second provider, and a backup copy (needed because there's no versioning).
- **The financial case depends on video and internet egress pricing**, which RumptyCloud doesn't publish for buckets. Get a written quote before relying on it.
- **Latency:** a Lagos region should cut upload/download latency for Nigerian users compared with a US-region Firebase bucket. This is plausible but **unmeasured**; measure from MTN/Airtel/Glo networks in staging (test T18).
- **Migration cost:** engineering (≈ 2–4 weeks for the phases 0–2 code), double storage during transition, backfill egress out of Firebase (GCS egress rates).
- **Recommendation:** decide only after the staging measurements and an egress quote. RumptyCloud should not be assumed cheaper.
