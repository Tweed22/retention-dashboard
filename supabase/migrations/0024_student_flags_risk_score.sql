-- ─────────────────────────────────────────────────────────────────────────
-- 0024_student_flags_risk_score
-- ─────────────────────────────────────────────────────────────────────────
-- Midterm Meeting risk is a score 0–4 in 0.5 steps (Tony 2026-10-22), not a
-- whole-number level. Scores below 1 mean "not tagged", so a stored tag
-- always holds 1.0–4.0. Color bands (client): 1–1.5 plain, 2–2.5 yellow,
-- 3–3.5 red, 4 purple. Replaces 0023's smallint `level`.
-- ─────────────────────────────────────────────────────────────────────────

alter table student_flags drop constraint if exists student_flags_level_check;
alter table student_flags rename column level to risk_score;
alter table student_flags alter column risk_score type numeric(2,1) using risk_score::numeric(2,1);
alter table student_flags alter column risk_score set default 1;
alter table student_flags
  add constraint student_flags_risk_score_check
  check (risk_score between 1 and 4 and risk_score * 2 = trunc(risk_score * 2));
