-- 0006 — Persist class year on not_returning_reports.
--
-- WHY: Tony 2026-05-07 wants Class (Freshman/Sophomore/etc.) shown and
-- filterable on the NR list. Like sport+major (migration 0005), storing
-- class_year on the NR row itself means a manual edit survives a refresh
-- AND the value is preserved across the Pending → Withdrawn transition
-- when the withdrawal CSV doesn't carry class info.

alter table not_returning_reports add column if not exists class_year text;
