-- Retention Dashboard — initial schema + RLS policies
-- Maps directly to ARCHITECTURE_PLAN.md section 4.
-- Apply via Supabase SQL Editor or `supabase db push`.

-- ─────────────────────────────────────────────────────────────────────────
-- Extensions
-- ─────────────────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;          -- gen_random_uuid()

-- ─────────────────────────────────────────────────────────────────────────
-- committee_members
-- ─────────────────────────────────────────────────────────────────────────
-- Allowlist of email addresses permitted to receive a magic-link login.
-- Tony's row should have role='admin'; everyone else is 'member'.
-- Soft-disable via is_active=false rather than DELETE so audit trail survives.
create table if not exists committee_members (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  display_name  text,
  role          text not null default 'member' check (role in ('admin', 'member')),
  added_by      uuid,
  added_at      timestamptz not null default now(),
  is_active     boolean not null default true
);

-- ─────────────────────────────────────────────────────────────────────────
-- Helper functions for RLS policies
-- ─────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER lets these functions read committee_members even when
-- the caller doesn't have direct SELECT on it. Without that the policies
-- on committee_members itself would create a chicken-and-egg lookup loop.

create or replace function public.is_active_committee_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from committee_members
    where lower(email) = lower(auth.email())
      and is_active = true
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from committee_members
    where lower(email) = lower(auth.email())
      and role = 'admin'
      and is_active = true
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- terms
-- ─────────────────────────────────────────────────────────────────────────
-- "Current term" = the row whose start_date is the most recent ≤ today.
-- Window for current-term filters = [current.start_date, next.start_date).
-- If no next term exists, upper bound falls back to today (open-ended).
create table if not exists terms (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  start_date  date not null unique,
  notes       text,
  created_by  uuid,
  created_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- csv_snapshots — every CSV upload creates one row
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists csv_snapshots (
  id            uuid primary key default gen_random_uuid(),
  uploaded_by   uuid,
  uploaded_at   timestamptz not null default now(),
  source_files  jsonb,                  -- {unreg:'foo.csv', reg:'...', new:'...', withdrawals:'...'}
  student_count int,
  notes         text
);

create index if not exists idx_csv_snapshots_uploaded_at on csv_snapshots (uploaded_at desc);

-- ─────────────────────────────────────────────────────────────────────────
-- students
-- ─────────────────────────────────────────────────────────────────────────
-- Phase 1 model: delete-and-replace on each admin upload (snapshot_id
-- tracks which upload the row came from). Phase 4 may move to a historical
-- retention model with a "current students" view.
create table if not exists students (
  id              text primary key,
  first_name      text,
  last_name       text,
  email           text,
  major           text,
  advisor         text,
  sports          text[],
  class_year      text,
  holds           text[],
  is_new_student  boolean default false,
  is_registered   boolean default false,
  snapshot_id     uuid references csv_snapshots(id) on delete set null,
  updated_at      timestamptz not null default now()
);

create index if not exists idx_students_snapshot on students (snapshot_id);
create index if not exists idx_students_class_year on students (class_year);

-- ─────────────────────────────────────────────────────────────────────────
-- snapshot_metrics — pre-aggregated metrics per snapshot
-- ─────────────────────────────────────────────────────────────────────────
-- Public reads come from this table — never from students directly. That
-- enforces the "no per-student data on the public Summary" rule.
create table if not exists snapshot_metrics (
  snapshot_id          uuid primary key references csv_snapshots(id) on delete cascade,
  total_returning      int,
  total_registered     int,
  registration_rate    numeric,
  total_new            int,
  new_registered       int,
  total_holds          int,
  holds_advising       int,
  holds_account        int,
  holds_registrar      int,
  holds_missing_docs   int,
  holds_immunization   int,
  can_register         int,
  not_returning_count  int,
  withdrawals_this_term int,
  high_risk_count      int,
  critical_risk_count  int,
  by_class_year        jsonb,
  by_advisor           jsonb,
  by_major             jsonb,
  by_sport             jsonb,
  computed_at          timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- withdrawals
-- ─────────────────────────────────────────────────────────────────────────
-- Authoritative completed withdrawals from the registrar's CSV.
-- The current-term filter uses last_active_date — NOT processed_date.
-- Re-uploads upsert by (student_id, last_active_date); duplicates collapse.
-- student_id is intentionally NOT a FK because withdrawal records often
-- reference students who are no longer in the active students snapshot
-- (they've withdrawn). Self-contained name/contact columns let us render
-- withdrawal data without joining to students.
create table if not exists withdrawals (
  id                uuid primary key default gen_random_uuid(),
  student_id        text,
  last_active_date  date not null,
  processed_date    date,
  withdrawal_reason text,
  withdrawal_type   text,
  first_name        text,
  last_name         text,
  email             text,
  major             text,
  advisor           text,
  class_year        text,
  term_id           uuid references terms(id) on delete set null,
  snapshot_id       uuid references csv_snapshots(id) on delete set null,
  source_filename   text,
  created_at        timestamptz not null default now(),
  unique (student_id, last_active_date)
);

create index if not exists idx_withdrawals_lda      on withdrawals (last_active_date);
create index if not exists idx_withdrawals_term     on withdrawals (term_id);
create index if not exists idx_withdrawals_student  on withdrawals (student_id);

-- ─────────────────────────────────────────────────────────────────────────
-- risk_overrides
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists risk_overrides (
  id              uuid primary key default gen_random_uuid(),
  student_id      text references students(id) on delete set null,
  score           int check (score between 0 and 100),
  category        text check (category in ('Low','Moderate','High','Critical')),
  rationale       text,
  submitter_name  text,
  submitter_email text,
  submitter_uid   uuid,                   -- auth.uid() at submission time
  created_at      timestamptz not null default now(),
  is_hidden       boolean not null default false
);

create index if not exists idx_risk_overrides_student on risk_overrides (student_id) where is_hidden = false;

-- ─────────────────────────────────────────────────────────────────────────
-- not_returning_reports
-- ─────────────────────────────────────────────────────────────────────────
-- The shared NR list. Either human-entered through the gated NR form, OR
-- auto-created by withdrawal CSV ingestion (in which case
-- source_withdrawal_id points back at the source row for idempotent re-imports).
create table if not exists not_returning_reports (
  id                   uuid primary key default gen_random_uuid(),
  student_id           text,
  student_name         text,
  reason               text,
  withdrawal_status    text check (withdrawal_status in ('Pending','Withdrawn')),
  notes                text,
  submitter_name       text,
  submitter_email      text,
  submitter_uid        uuid,
  source_withdrawal_id uuid references withdrawals(id) on delete set null,
  created_at           timestamptz not null default now(),
  is_hidden            boolean not null default false
);

create index if not exists idx_nrr_student      on not_returning_reports (student_id) where is_hidden = false;
create index if not exists idx_nrr_source_wd    on not_returning_reports (source_withdrawal_id);

-- ─────────────────────────────────────────────────────────────────────────
-- timeline_events — for the future Trends tab (Phase 3)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists timeline_events (
  id            uuid primary key default gen_random_uuid(),
  event_date    date not null,
  end_date      date,
  category      text check (category in ('Registration','Outreach','Deadline','Communication','Other')),
  source_office text,
  title         text not null,
  description   text,
  color         text,
  created_by    uuid,
  created_at    timestamptz not null default now()
);

create index if not exists idx_timeline_events_date on timeline_events (event_date);

-- ─────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ─────────────────────────────────────────────────────────────────────────
-- Tiered model from ARCHITECTURE_PLAN.md section 3:
--   • snapshot_metrics: public SELECT (the only public surface)
--   • everything else:  committee SELECT, admin write

alter table committee_members        enable row level security;
alter table terms                    enable row level security;
alter table csv_snapshots            enable row level security;
alter table students                 enable row level security;
alter table snapshot_metrics         enable row level security;
alter table withdrawals              enable row level security;
alter table risk_overrides           enable row level security;
alter table not_returning_reports    enable row level security;
alter table timeline_events          enable row level security;

-- ── snapshot_metrics: PUBLIC read (anon allowed). No anon writes.
drop policy if exists "snapshot_metrics_anon_select" on snapshot_metrics;
create policy "snapshot_metrics_anon_select"
  on snapshot_metrics for select
  to anon, authenticated
  using (true);

drop policy if exists "snapshot_metrics_admin_all" on snapshot_metrics;
create policy "snapshot_metrics_admin_all"
  on snapshot_metrics for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── committee_members: only authenticated committee can read; only admin can write.
drop policy if exists "committee_members_select" on committee_members;
create policy "committee_members_select"
  on committee_members for select
  to authenticated
  using (public.is_active_committee_member());

drop policy if exists "committee_members_admin_all" on committee_members;
create policy "committee_members_admin_all"
  on committee_members for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── students / withdrawals / csv_snapshots / terms / timeline_events:
--    committee read, admin write.
do $$
declare t text;
begin
  for t in
    select unnest(array[
      'students', 'withdrawals', 'csv_snapshots', 'terms', 'timeline_events'
    ])
  loop
    execute format($f$
      drop policy if exists "%1$s_committee_select" on %1$I;
      create policy "%1$s_committee_select"
        on %1$I for select
        to authenticated
        using (public.is_active_committee_member());

      drop policy if exists "%1$s_admin_all" on %1$I;
      create policy "%1$s_admin_all"
        on %1$I for all
        to authenticated
        using (public.is_admin())
        with check (public.is_admin());
    $f$, t);
  end loop;
end $$;

-- ── risk_overrides + not_returning_reports:
--    committee SELECT (filtered to is_hidden=false on the client)
--    committee INSERT (any committee member can submit)
--    admin UPDATE/DELETE only (moderation; submitters can't take it back)
do $$
declare t text;
begin
  for t in
    select unnest(array['risk_overrides', 'not_returning_reports'])
  loop
    execute format($f$
      drop policy if exists "%1$s_committee_select" on %1$I;
      create policy "%1$s_committee_select"
        on %1$I for select
        to authenticated
        using (public.is_active_committee_member());

      drop policy if exists "%1$s_committee_insert" on %1$I;
      create policy "%1$s_committee_insert"
        on %1$I for insert
        to authenticated
        with check (public.is_active_committee_member());

      drop policy if exists "%1$s_admin_update" on %1$I;
      create policy "%1$s_admin_update"
        on %1$I for update
        to authenticated
        using (public.is_admin())
        with check (public.is_admin());

      drop policy if exists "%1$s_admin_delete" on %1$I;
      create policy "%1$s_admin_delete"
        on %1$I for delete
        to authenticated
        using (public.is_admin());
    $f$, t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Realtime — subscribe clients to csv_snapshots so they refresh on upload
-- ─────────────────────────────────────────────────────────────────────────
-- Supabase enables realtime per-table via the supabase_realtime publication.
alter publication supabase_realtime add table csv_snapshots;
alter publication supabase_realtime add table snapshot_metrics;
alter publication supabase_realtime add table not_returning_reports;

-- ─────────────────────────────────────────────────────────────────────────
-- Bootstrap: seed Tony's admin row (REPLACE THE EMAIL before running)
-- ─────────────────────────────────────────────────────────────────────────
-- This INSERT is here so the migration is self-contained — once it runs,
-- Tony can immediately sign in with magic-link and have admin access.
-- IMPORTANT: change the email below to the one Tony will sign in with.
insert into committee_members (email, display_name, role)
values ('anthony.weed@gmail.com', 'Tony Weed', 'admin')
on conflict (email) do update set role = 'admin', is_active = true;
