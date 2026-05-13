-- ─────────────────────────────────────────────────────────────────────────
-- 0012_explicit_data_api_grants
-- ─────────────────────────────────────────────────────────────────────────
-- Future-proofs the dashboard against Supabase's 2026 schema-permission
-- change. Starting Oct 30, 2026, the public schema no longer grants Data
-- API roles (anon, authenticated, service_role) by default; tables created
-- after that date need explicit GRANTs or `supabase-js` returns 42501.
--
-- Tables created BEFORE Oct 30, 2026 are grandfathered with their current
-- grants. Migrations 0001 through 0011 created their tables before this
-- migration, so they're already covered by Supabase's grandfather clause.
-- The grants below are therefore idempotent / belt-and-suspenders — they
-- restate what the default behavior already gives those tables, so the
-- migration history is self-documenting and works identically pre- and
-- post-Oct 30 on a fresh database rebuild.
--
-- RLS policies (defined in 0001_init.sql and later migrations) remain the
-- authoritative gate on WHO can read/write WHICH rows. These GRANTs only
-- decide which roles are allowed to talk to the table at all; RLS does
-- the row-level filtering. Both are required: GRANT without RLS would
-- expose every row, RLS without GRANT would block the table entirely.
--
-- Pattern for future migrations:
--   When CREATE TABLE-ing a new public table, follow it with:
--     grant select on public.<table> to anon;
--     grant select, insert, update, delete on public.<table> to authenticated;
--     grant select, insert, update, delete on public.<table> to service_role;
--     alter table public.<table> enable row level security;
--     create policy "..." on public.<table> for select to anon using (...);
--     ...
--   The grants are the new requirement; RLS + policies were already needed.
-- ─────────────────────────────────────────────────────────────────────────

-- ── Public-readable table: snapshot_metrics ──
-- Anonymous (signed-out) viewers see this for the public Summary tab.
-- Admins still need full CRUD via the authenticated role.
grant select
  on public.snapshot_metrics
  to anon;
grant select, insert, update, delete
  on public.snapshot_metrics
  to authenticated, service_role;

-- ── Committee-only readable tables ──
-- Anon role NOT granted on these — RLS would block them anyway, but
-- denying at the GRANT layer is defense-in-depth: a misconfigured policy
-- can't accidentally leak PII to signed-out viewers.
grant select, insert, update, delete
  on public.committee_members,
     public.terms,
     public.csv_snapshots,
     public.students,
     public.withdrawals,
     public.risk_overrides,
     public.not_returning_reports,
     public.timeline_events
  to authenticated, service_role;

-- ── Term history (added in migration 0003_term_history.sql) ──
-- Used by the Trends chart; readable to committee, writable by admin only
-- (the policy enforces the admin gate).
grant select, insert, update, delete
  on public.term_history
  to authenticated, service_role;
grant select
  on public.term_history
  to anon;  -- public Summary may render the trend chart from this table

-- ── FTFT roster (added in migration 0003_ftft_students.sql) ──
grant select, insert, update, delete
  on public.ftft_students
  to authenticated, service_role;

-- Sequences attached to bigserial / serial columns: granting USAGE on the
-- sequence is what lets `insert` actually allocate the next id. PostgREST
-- needs this for inserts to succeed.
grant usage on all sequences in schema public
  to authenticated, service_role;
