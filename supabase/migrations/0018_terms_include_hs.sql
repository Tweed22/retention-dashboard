-- ─────────────────────────────────────────────────────────────────────────
-- 0018_terms_include_hs
-- ─────────────────────────────────────────────────────────────────────────
-- Per-term admin switch: whether high-school dual-enrollment students
-- (class_cde 'HS' on the term's student listing) count toward Eligible to
-- Return. Lives on the term row so every viewer sees the same numbers and
-- each term's cohort carries its own choice. Defaults to excluded.
-- Admin write / committee read come from the existing terms policies.
-- ─────────────────────────────────────────────────────────────────────────

alter table terms
  add column if not exists include_hs boolean not null default false;
