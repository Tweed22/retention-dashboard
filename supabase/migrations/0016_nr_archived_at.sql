-- ─────────────────────────────────────────────────────────────────────────
-- 0016_nr_archived_at
-- ─────────────────────────────────────────────────────────────────────────
-- Distinguishes NR rows archived by the admin "Start new cycle" action from
-- rows a committee member removed (both set is_hidden = true).
--
-- The withdrawal auto-sync skips re-importing a withdrawal whose NR row was
-- removed by a person. Archived rows must NOT block re-import: a withdrawal
-- whose last-active date falls in the new term (e.g. a student who left in
-- week 1 of fall, originally synced during the prior cycle) still needs an
-- NR row in the new cycle.
--
-- Reversal of a cycle archive:
--   update not_returning_reports
--      set is_hidden = false, archived_at = null
--    where archived_at = '<timestamp of the archive>';
-- ─────────────────────────────────────────────────────────────────────────

alter table not_returning_reports
  add column if not exists archived_at timestamptz;
