# Part 18 — Feature Matrix

Synthesized from Parts 3–10. "Implemented %" is this audit's own judgment call, not a codebase-tracked metric. "Reuse in V2?" is answered at the *concept* level here; Part 22 answers it at the *code* level.

| Feature | Implemented % | Working? | Needs redesign? | Needs rewrite? | Priority | Reuse in V2? |
|---|---|---|---|---|---|---|
| Job posting | 95% | Yes | No | No | — | Yes |
| Quote submission/accept/reject | 100% | Yes | No | No | — | Yes |
| Chat (text/image/negotiation) | 80% | Yes | Yes (read receipts, typing, agreement-awareness) | No | Medium | Yes |
| Agreement Confirmation checkpoint | 90% (backend) / 60% (surfaced in UI) | Yes, but invisible from chat | Yes — needs surfacing in chat | No | **High** | Yes |
| Escrow deposit | 100% | Yes | No | No | — | Yes |
| Escrow payout (artisan gets paid) | 90% (code) / 0% (verified live) | **Unverified** | No | No | **Critical — verify before relying on it** | Yes, pending verification |
| Milestone/material payments | 0% | N/A | — | Build from scratch | Medium | New build |
| Refund | 0% | N/A | — | Build from scratch | Medium | New build |
| Live GPS tracking | 0% | N/A | — | Build from scratch | Medium | New build |
| Progress-stage tracker (manual) | 100% | Yes | No | No | — | Yes |
| Trust Score computation | 100% | Yes | No | No | — | Yes |
| Trust Score → ranking | 0% | No — ranks by a different formula | Yes | Yes | **High** | Fix, don't rebuild |
| Trust Score response-time input | 0% (frozen constant) | No | — | Yes (instrumentation) | Medium | Fix the input, not the formula |
| Verification (selfie/ID + defer) | 100% | Yes | No | No | — | Yes |
| Reviews | 100% | Yes | No | No | — | Yes |
| Disputes (raise/respond/resolve) | 95% | Yes (customer-only raise, confirmed) | No | No | — | Yes |
| Notifications (in-app + push) | 70% | Yes for the 12 whitelisted types | Yes — reminder types, per-category prefs | No | Medium | Yes, extend |
| Wallet | 70% | Yes, non-milestone-aware | Yes, once milestones exist | No | Low (works today) | Yes |
| Admin dashboard (12 sections) | 85% | Yes | Partial (pagination, mobile) | No | Medium | Yes |
| Escrow Monitoring (admin) | 0% | N/A | — | Build from scratch | Medium | New build |
| Trust Score Management (admin) | 20% (visible per-row only) | Partial | Yes | No | Low | Extend |
| Guest/demo mode | 0% | Not present | — | — | N/A | Product decision needed |
| Phone auth | 0% (dead code) | Unrouted | — | — | Low | Product decision needed |

## Reading this table
The two rows that matter most for a rebuild decision are **Escrow payout** (real code, real risk — genuinely unverified, not genuinely broken) and **Trust Score → ranking** (a cheap fix, not a rebuild — the score is correct, only the consumer of it is wrong). Both are elaborated fully in Part 22.
