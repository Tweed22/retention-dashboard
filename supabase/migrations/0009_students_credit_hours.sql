-- 0009 — Persist total enrolled credit hours per student.
--
-- WHY: Tony 2026-05-07 wants to see how many credit hours each registered
-- student is enrolled in. The registered CSV has one row per enrollment
-- with a credit_hrs column; the dashboard sums these per student during
-- ingest. Storing the per-student total on the students table lets every
-- committee member see the same number without re-uploading.

alter table students add column if not exists credit_hours numeric;
