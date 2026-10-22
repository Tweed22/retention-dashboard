-- ─────────────────────────────────────────────────────────────────────────
-- 0019_term_cohort_status_override
-- ─────────────────────────────────────────────────────────────────────────
-- Admin override of a cohort member's status, for students the reports
-- can't place correctly (e.g. a December graduate whose graduation hold is
-- missing, or a dual-enrollment student whose class code isn't HS).
--   'graduating' → excluded from every number, like a Graduating NR tag
--   'hs'         → treated as high-school dual enrollment (HS toggle rules)
-- Cohort re-uploads upsert without this column, so overrides persist.
-- Admin write / committee read come from the existing term_cohort policies.
-- ─────────────────────────────────────────────────────────────────────────

alter table term_cohort
  add column if not exists status_override text
  check (status_override in ('graduating', 'hs'));
