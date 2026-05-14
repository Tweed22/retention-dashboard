-- ─────────────────────────────────────────────────────────────────────────
-- 0014_students_career_gpa
-- ─────────────────────────────────────────────────────────────────────────
-- Adds the registrar's `career_gpa` value to each student row. Source is
-- the same registered CSV that already provides hrs_enrolled and
-- pt_ft_sts (per migration 0011). Stored as numeric so half-points (e.g.,
-- 3.45) survive round-trips.
--
-- Privacy: the dashboard's Registered tab shows GPA ONLY to admins via
-- the existing .admin-only CSS class (already wired in the auth gating
-- block — body.auth-committee hides .admin-only with !important). The
-- API still returns career_gpa to any authenticated viewer; a committee
-- member with DevTools open could read it from the JSON. If that level
-- of confidentiality is required later, this column should move behind
-- a view that returns career_gpa only when auth.uid() is in
-- committee_members with role='admin'. For now the client-side gate is
-- the working policy. Tony 2026-05-13.
-- ─────────────────────────────────────────────────────────────────────────

alter table students
  add column if not exists career_gpa numeric;

-- No new grants — column inherits the students-table grants set in
-- migration 0012_explicit_data_api_grants.sql.
