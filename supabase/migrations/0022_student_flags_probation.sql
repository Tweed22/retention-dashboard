-- ─────────────────────────────────────────────────────────────────────────
-- 0022_student_flags_probation
-- ─────────────────────────────────────────────────────────────────────────
-- Adds the P1 / P2 academic probation tags (per term, mutually exclusive —
-- the client removes the other level when one is set).
-- ─────────────────────────────────────────────────────────────────────────

alter table student_flags drop constraint if exists student_flags_flag_check;
alter table student_flags
  add constraint student_flags_flag_check
  check (flag in ('midterm_meeting', 'provisional', 'p1', 'p2'));
