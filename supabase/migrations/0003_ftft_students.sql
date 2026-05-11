-- 0003 — First-Time Full-Time (FTFT) roster
--
-- Tony 2026-05-11: FTFT cohort is identified by a separate CSV upload (the
-- registrar exports the roster as a flat list of student IDs). Storing the
-- roster in Supabase means every committee member sees the same FTFT badges
-- and counts — without this migration, FTFT data only lives in the
-- uploading admin's localStorage.
--
-- Design: standalone table keyed on student_id (TEXT). Not a FK to students
-- because the FTFT roster may include IDs that don't yet appear in the
-- registered / unregistered / new students CSVs (similar to withdrawals).
-- Each upload replaces the entire roster (DELETE + INSERT) — the roster is
-- meant to represent the current cohort, not a historical accumulation.

create table if not exists ftft_students (
  id          text primary key,
  snapshot_id uuid references csv_snapshots(id) on delete set null,
  added_at    timestamptz not null default now()
);

create index if not exists idx_ftft_students_snapshot on ftft_students (snapshot_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Row-Level Security — matches the pattern used by students/withdrawals.
-- Committee members can SELECT, only admins can INSERT/UPDATE/DELETE.
-- ─────────────────────────────────────────────────────────────────────────
alter table ftft_students enable row level security;

drop policy if exists "ftft_students_committee_select" on ftft_students;
create policy "ftft_students_committee_select"
  on ftft_students for select
  to authenticated
  using (public.is_active_committee_member());

drop policy if exists "ftft_students_admin_all" on ftft_students;
create policy "ftft_students_admin_all"
  on ftft_students for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- Realtime — committee members get an immediate refresh when an admin
-- uploads a new FTFT roster, matching the csv_snapshots subscription.
-- ─────────────────────────────────────────────────────────────────────────
alter publication supabase_realtime add table ftft_students;
