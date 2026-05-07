-- 0005 — Persist sport and major on not_returning_reports.
--
-- WHY: Tony 2026-05-07 wants Sport(s) and Major shown on every NR row,
-- editable, and durable across refreshes. They were previously enriched
-- on the fly from the students table at load time, which meant: (a) a
-- manually-typed value wouldn't survive a refresh, and (b) when a Pending
-- student transitioned to Withdrawn via the withdrawal CSV (which carries
-- no athletics data), the sport info was lost. Storing on the NR row
-- itself fixes both — the row is now self-contained, and the auto-sync
-- can leave sport untouched on update so it's preserved through the
-- Pending → Withdrawn transition.

alter table not_returning_reports add column if not exists sport text;
alter table not_returning_reports add column if not exists major text;
