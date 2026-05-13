-- ─────────────────────────────────────────────────────────────────────────
-- 0011_students_pt_ft
-- ─────────────────────────────────────────────────────────────────────────
-- Adds the Part-Time / Full-Time enrollment status that comes from the
-- registrar's new registered report column `pt_ft_sts`.
--
-- Storage: a single-char text column ('P' / 'F') or NULL when unknown.
-- We keep it text rather than an enum so future codes (e.g. 'H' for half-
-- time, 'L' for less-than-half) can be added without another migration.
--
-- Used by the Registered, Can Register, and Holds tabs to show a small
-- chip per student. The Registered tab also gets a filter dropdown
-- (All / Full-Time / Part-Time) driven off this column.
-- ─────────────────────────────────────────────────────────────────────────

alter table students
  add column if not exists pt_ft_status text;

-- No index needed — student lookups are by primary key, and the rare
-- filter scan over a few hundred rows is fast without one.
