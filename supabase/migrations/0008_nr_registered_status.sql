-- 0008 — Allow "Registered" as a third withdrawal_status value.
--
-- WHY: Tony 2026-05-07 wants a blue "Registered" chip in the Withdrawal
-- column for students on the NR list who are nonetheless still enrolled
-- in courses. Replaces the soft-yellow row tint with an explicit status
-- value that's filterable, persistable, and visually distinct from
-- Pending (amber) and Withdrawn (red).

alter table not_returning_reports drop constraint if exists not_returning_reports_withdrawal_status_check;
alter table not_returning_reports add constraint not_returning_reports_withdrawal_status_check
  check (withdrawal_status in ('Pending', 'Withdrawn', 'Registered'));
