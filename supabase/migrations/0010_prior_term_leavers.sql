-- ─────────────────────────────────────────────────────────────────────────
-- 0010_prior_term_leavers
-- ─────────────────────────────────────────────────────────────────────────
-- Adds the "Prior Fall→Spring leavers" count to the dashboard's persisted
-- state. This is the N in the Fall-to-Fall Persistence Rate formula:
--
--   FallToFall = Returning Registered ÷ (Eligible to Return + N)
--
-- where N = students who started the previous Fall but did NOT enroll the
-- following Spring (excluding graduates). Those students were eligible to
-- come back this Fall but didn't, so they belong in the Fall-to-Fall
-- denominator. The dashboard's live "Eligible to Return" only counts
-- students currently in the Spring roster, so we have to add N back.
--
-- Storage strategy:
--   • terms.prior_term_leavers — admin-edited via Settings. Synced from the
--     admin's browser on each CSV upload (Step 3 of pushDataToSupabase),
--     and restored into termSettings on dashboard load. Lives on the
--     "current term" row so it follows the term it's about.
--   • snapshot_metrics.prior_term_leavers — copy of the value at snapshot
--     time, so the public Summary can render the Fall-to-Fall rate without
--     needing terms access. Stored alongside the rate itself for caching.
--   • snapshot_metrics.fall_to_fall_rate — pre-computed Fall-to-Fall rate
--     (numeric percent, one decimal). Lets renderPublicSummary display it
--     without joining additional tables.
-- ─────────────────────────────────────────────────────────────────────────

alter table terms
  add column if not exists prior_term_leavers int not null default 0;

alter table snapshot_metrics
  add column if not exists prior_term_leavers int default 0,
  add column if not exists fall_to_fall_rate numeric;

-- No index needed: terms is a tiny table (a handful of rows per academic
-- year), and snapshot_metrics queries use the primary key. The new columns
-- inherit the table's existing RLS policies (anon SELECT on snapshot_metrics,
-- committee SELECT + admin write on terms).
