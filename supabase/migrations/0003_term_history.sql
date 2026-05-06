-- 0003 — Term history: stores per-day historical snapshots that pre-date the
-- automated csv_snapshots flow. Tony populates this manually for terms before
-- the dashboard existed, then the trend chart on Summary reads from it.

create table if not exists term_history (
  id                  uuid primary key default gen_random_uuid(),
  snapshot_date       date not null,
  term_label          text,                  -- e.g. 'Fall 2026 registration'
  registered_count    int,
  holds_count         int,
  registration_rate   numeric,               -- e.g. 73.9 (percentage)
  notes               text,
  created_at          timestamptz not null default now(),
  unique (snapshot_date, term_label)
);

alter table term_history enable row level security;

drop policy if exists "term_history_committee_select" on term_history;
create policy "term_history_committee_select"
  on term_history for select
  to authenticated
  using (public.is_active_committee_member());

drop policy if exists "term_history_admin_all" on term_history;
create policy "term_history_admin_all"
  on term_history for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Backfill: Tony's Spring → Fall 2026 historical registration data.
-- Re-running this is safe (ON CONFLICT updates the existing row).
insert into term_history (snapshot_date, term_label, registered_count, holds_count, registration_rate) values
  ('2026-03-23', 'Fall 2026 registration', 16,  471, 2.7),
  ('2026-03-24', 'Fall 2026 registration', 17,  425, 2.9),
  ('2026-03-25', 'Fall 2026 registration', 79,  386, 13.4),
  ('2026-03-26', 'Fall 2026 registration', 90,  325, 15.2),
  ('2026-03-27', 'Fall 2026 registration', 107, 282, 18.1),
  ('2026-03-30', 'Fall 2026 registration', 137, 241, 23.2),
  ('2026-03-31', 'Fall 2026 registration', 189, 220, 32.0),
  ('2026-04-01', 'Fall 2026 registration', 238, 204, 40.3),
  ('2026-04-02', 'Fall 2026 registration', 317, 189, 53.6),
  ('2026-04-03', 'Fall 2026 registration', 336, 185, 56.9),
  ('2026-04-06', 'Fall 2026 registration', 351, 176, 59.4),
  ('2026-04-07', 'Fall 2026 registration', 355, 173, 60.1),
  ('2026-04-08', 'Fall 2026 registration', 360, null, 60.9),
  ('2026-04-13', 'Fall 2026 registration', 370, 149, 62.6),
  ('2026-04-14', 'Fall 2026 registration', 369, 146, 62.4),
  ('2026-04-15', 'Fall 2026 registration', 372, 144, 62.9),
  ('2026-04-16', 'Fall 2026 registration', 377, 143, 63.8),
  ('2026-04-17', 'Fall 2026 registration', 379, 142, 64.1),
  ('2026-04-20', 'Fall 2026 registration', 397, 138, 67.2),
  ('2026-04-23', 'Fall 2026 registration', 408, 136, 69.0),
  ('2026-04-24', 'Fall 2026 registration', 410, 132, 69.4),
  ('2026-04-27', 'Fall 2026 registration', 417, 125, 70.6),
  ('2026-04-28', 'Fall 2026 registration', 419, 119, 70.9),
  ('2026-04-29', 'Fall 2026 registration', 420, 118, 71.1),
  ('2026-04-30', 'Fall 2026 registration', 422, 117, 71.4),
  ('2026-05-04', 'Fall 2026 registration', 437, 108, 73.9),
  ('2026-05-06', 'Fall 2026 registration', 437, 108, 73.9)
on conflict (snapshot_date, term_label) do update set
  registered_count  = excluded.registered_count,
  holds_count       = excluded.holds_count,
  registration_rate = excluded.registration_rate;
