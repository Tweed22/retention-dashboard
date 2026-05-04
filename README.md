# Retention Dashboard

Tracks student registration and retention each term. Public Summary tab shows aggregate metrics (returning rate, holds breakdown, withdrawals, reasons-not-returning chart). Gated tabs show per-student detail behind a magic-link committee allowlist.

## Repo layout

| Path | Purpose |
|---|---|
| `retention-dashboard.html` | Single-file dashboard. Currently runs locally (drop CSVs in browser). Phase 1 wires it to Supabase. |
| `ARCHITECTURE_PLAN.md` | Source of truth for design decisions. Read this first before changing anything material. |
| `DEPLOYMENT.md` | Step-by-step setup of Supabase + Cloudflare Pages accounts. Read after the architecture plan. |
| `supabase/migrations/0001_init.sql` | Database schema + RLS policies. Apply via Supabase SQL Editor or `supabase db push`. |
| `sample_data/` *(gitignored)* | Real registrar CSVs — never commit; contains student PII. |

## Status (2026-05-04)

- Local dashboard works: 4 CSV uploads (unregistered, registered, new, withdrawals), Summary + Holds + Can Register + New Students + Withdrawals + Not Returning tabs, term-window-filtered withdrawals auto-feed the Not Returning list, per-tab CSV export.
- Supabase migration written; RLS policies enforce public-Summary / committee-detail / admin-write tiers.
- Awaiting Tony's Supabase project URL + anon key + Cloudflare Pages URL before Phase 1 client-side wiring begins (see DEPLOYMENT.md for the account-setup checklist).

## License

Internal use only — not licensed for redistribution.
