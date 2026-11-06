# RumptyCloud object storage — capability audit (H1.2)

**Stage:** H1.2 audit only. No bucket, key or resource was created.
**Sources:** `docs.rumptycloud.com` pages `buckets/introduction`, `buckets/create-a-bucket`, `buckets/uploading`, `buckets/access-keys-and-s3`, `billing/introduction`, `settings/api-keys`, plus `rumptycloud.com` and `rumptycloud.com/pricing`, read on 5 November 2026.
**Legend:**
- **V**: verified in the official docs;
- **ND**: not documented (treat as unavailable until proven by a test in a staging bucket);
- **I**: inferred from documented behaviour (states the reasoning).

| Capability | Status | Detail |
|---|---|---|
| S3-compatible API | **V** | Endpoint `https://s3.rumptycloud.com`, region `olas-closet`, **path-style** addressing. Works with AWS SDKs (JS v3, Boto3), AWS CLI, rclone, MinIO `mc` |
| Bucket management | **V** | Dashboard; names 2–63 chars, unique per workspace. Deleting a bucket deletes its files and keys |
| Public vs private buckets | **V** | "Public images": permanent public read URLs (`assets.rumptycloud.com/projects/<id>/<bucket>/<file>`), uploads use public-read ACL. "Private images": not public-read; the app requests signed read URLs |
| Signed upload URLs (presigned PUT) | **V** | Example with `getSignedUrl` and `expiresIn: 300`. The request must send the signed Content-Type or it fails (`SignatureDoesNotMatch`) |
| Signed download URLs | **V / I** | Private buckets serve files through "signed read URLs" that expire; "objects are never directly public-read". Presigned **GET** has no code example; confirm by test |
| Temporary / STS credentials | **ND** | Only static per-bucket access keys are documented |
| Key scoping | **V** | **One key = one bucket.** Permissions list/read/write/delete in any combination; **no folder/prefix scoping**; permissions can't be edited (create a new key, revoke the old). Presigned URLs carry the signing key's permissions |
| Object-level permissions / ACLs | **V (partial)** | Write permission covers setting ACLs and tags; public buckets apply public-read ACLs. Per-object policies: **ND** |
| File-size limits | **V** | Single PutObject up to **5 GB**; multipart: parts ≥ 5 MB (except the last), ≤ 10,000 parts |
| Supported media types | **V (dashboard)** | Dashboard uploads: PNG, JPEG, WebP, GIF, SVG, PDF, TXT, HTML, Markdown, CSV, DOCX, MP4, WebM, MOV, MKV, AVI, HLS. Limits on API uploads: **ND** |
| Multipart upload | **V** | Start / upload part / copy part / complete / list / abort; needs write only. Incomplete uploads auto-deleted **7 days** after start |
| Resumable uploads | **I** | Possible through multipart (re-upload missing parts). No resumable-session protocol is documented |
| Video delivery | **ND** | HLS files are accepted for upload; transcoding, streaming and range requests on public URLs aren't documented (GetObject range reads are supported via the API) |
| Image transformation / resizing | **ND** | Nothing documented; assume none |
| CDN / caching | **ND** | Public URL host `assets.rumptycloud.com`; CDN, cache headers and edge locations aren't documented |
| CORS | **V** | Dashboard only (no API); ≤ 20 allowed origins; wildcard subdomains allowed. Mobile apps don't need CORS |
| Encryption in transit | **V** | HTTPS endpoints |
| Encryption at rest | **ND** | — |
| Versioning / object lock | **V: not available** | "Versioning can't be turned on"; deleted or overwritten objects can't be recovered; no object lock |
| Backup / replication / durability | **ND** | No durability figure; single region **lagos-1**, single zone; "redundancy is limited for now" (website) |
| Deletion behaviour | **V** | DeleteObject / DeleteObjects (≤ 1,000 per call); bucket delete removes everything. No soft delete |
| Usage monitoring | **V (partial)** | Dashboard stats; billing "Included usage". Request-level logs or metrics: **ND** |
| Rate limits | **V** | **600 write requests per minute per key** (503 SlowDown); reads not limited per key |
| API authentication | **V** | S3 SigV4 with per-bucket access keys; secret shown once; revocable immediately |
| Key rotation | **V (manual)** | Create a new key, switch, revoke the old one; no automatic rotation |
| Pricing | **V** | First **10 GB** free, then **$0.02/GB-month**; "in-network egress is free". **Internet egress price for buckets: ND**; request pricing: ND; prepaid credit in USD, **no spend alerts** |
| Region | **V** | One region, Lagos (`lagos-1`, zone `olas-closet`); more planned |
| Reliability | **V** | No SLA; status page exists (couldn't be read: client-rendered); support via Discord/GitHub |
| Compliance | **V** | No certifications claimed |

## Conclusions

1. **Technically usable for media:**
   - S3 API;
   - presigned PUT;
   - private buckets with signed reads;
   - multipart for video;
   - write-only and read-only keys.
2. **Material gaps for HandyTrust's private and sensitive media:**
   - no documented encryption at rest;
   - no durability or replication statement;
   - **no versioning** (an accidental or malicious delete is permanent);
   - single zone, no SLA;
   - internet egress price undocumented.
3. **Must be proven in a staging bucket before any design depends on them:**
   - presigned GET;
   - signed Content-Length / size limits;
   - DeleteObject on a missing key;
   - behaviour after key revocation;
   - throughput from Nigerian mobile networks.
