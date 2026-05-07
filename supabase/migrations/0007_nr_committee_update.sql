-- 0007 — Allow any active committee member to UPDATE not_returning_reports.
--
-- WHY: Tony 2026-05-07 wants committee members (not just admins) to edit
-- NR rows directly — change reasons, notes, sport, major, class year, and
-- soft-delete via the Remove button (which sets is_hidden=true). Limiting
-- writes to admins was overly restrictive for a small committee where
-- everyone is trusted to triage their own students.
--
-- The DELETE policy stays admin-only on principle: hard deletes are
-- irreversible and the UI never issues them anyway (Remove uses an UPDATE
-- to set is_hidden=true, which this new policy now permits).

drop policy if exists "not_returning_reports_admin_update" on not_returning_reports;
create policy "not_returning_reports_committee_update"
  on not_returning_reports for update
  to authenticated
  using (public.is_active_committee_member())
  with check (public.is_active_committee_member());
