-- ─────────────────────────────────────────────────────────────────────────
-- 0020_terms_include_pt
-- ─────────────────────────────────────────────────────────────────────────
-- Per-term admin switch: whether part-time students (pt_ft_sts 'P' on the
-- term's student listing) count toward Eligible to Return. Defaults to
-- counted, so turning the feature on changes no numbers until an admin
-- unticks it. Admin write / committee read come from the terms policies.
-- ─────────────────────────────────────────────────────────────────────────

alter table terms
  add column if not exists include_pt boolean not null default true;
