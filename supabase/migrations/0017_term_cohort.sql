-- ─────────────────────────────────────────────────────────────────────────
-- 0017_term_cohort
-- ─────────────────────────────────────────────────────────────────────────
-- Frozen base cohort for a term: the registrar's student listing report for
-- that term (e.g. the Fall 2026 listing while tracking Fall → Spring). When
-- a cohort exists for the current term, Eligible to Return is the cohort
-- (minus Graduating) instead of a set reconstructed from the daily
-- unregistered/registered rosters — so a student who drops off the daily
-- reports without a formal withdrawal surfaces as "Unaccounted" instead of
-- silently vanishing from the denominator.
--
-- One row per (term, student). Withdrawn students appear on the listing and
-- are intentionally kept: they were enrolled that term, so they were
-- eligible to return.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists term_cohort (
  term_id        uuid not null references terms(id) on delete cascade,
  student_id     text not null,
  first_name     text,
  last_name      text,
  class_cde      text,
  major          text,
  div_cde        text,
  hrs_enrolled   numeric,
  pt_ft_sts      text,
  uploaded_at    timestamptz not null default now(),
  primary key (term_id, student_id)
);

alter table term_cohort enable row level security;

drop policy if exists "term_cohort_committee_select" on term_cohort;
create policy "term_cohort_committee_select"
  on term_cohort for select
  to authenticated
  using (public.is_active_committee_member());

drop policy if exists "term_cohort_admin_all" on term_cohort;
create policy "term_cohort_admin_all"
  on term_cohort for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Explicit Data API grants (required for new public tables; see 0012).
grant select, insert, update, delete on public.term_cohort to authenticated;
grant select, insert, update, delete on public.term_cohort to service_role;
