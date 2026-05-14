-- ─────────────────────────────────────────────────────────────────────────
-- 0013_term_history_nr_rate
-- ─────────────────────────────────────────────────────────────────────────
-- Adds the Not-Returning percentage to each term_history snapshot so the
-- registration trend chart can render an inverted red volume from 100%
-- down by nr_rate%. This is the "students declared not returning" share
-- of the eligible-to-return cohort — distinct from the "didn't register
-- yet" share. Storing it as a percentage (one decimal) keeps the chart
-- math simple: y(100 - nr_rate) gives the bottom of the red area.
--
-- nr_rate is nullable on purpose. Historical snapshots written before
-- this migration won't have it; the chart silently skips the inverted
-- area for points where nr_rate IS NULL. Each new upload writes a value
-- forward, so historical-tab charts populate over time as new daily
-- snapshots accumulate.
--
-- Per Tony 2026-05-13: "I don't have data for this side, so we can use
-- current data point, but update in the future."
-- ─────────────────────────────────────────────────────────────────────────

alter table term_history
  add column if not exists nr_rate numeric;

-- No grants needed — term_history already has the standard public-select +
-- authenticated-CRUD grants from migration 0012 / 0001. Column inherits.
