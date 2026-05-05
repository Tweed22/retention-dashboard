-- 0002 — Drop FK on withdrawals.student_id, replace 'Complete' with
--        'Withdrawn' as the NR exited-status, and add self-contained
--        name/contact columns to withdrawals.
--
-- WHY: withdrawal students typically AREN'T in the active students snapshot
-- (they've left the institution), so the FK was rejecting upserts. The
-- migration drops the FK; the unique(student_id, last_active_date)
-- constraint still prevents duplicate rows.
--
-- Status semantics simplified per Tony 2026-05-04:
--   Pending   = paperwork not yet processed; committee has flagged the student
--   Withdrawn = formally withdrawn (paperwork processed, registrar confirmed)
-- (The previous 'Complete' value is migrated to 'Withdrawn'.)

-- 1) Drop the foreign key on student_id. Withdrawals is now an event log
--    that references student IDs without requiring the row to exist.
alter table withdrawals drop constraint if exists withdrawals_student_id_fkey;

-- 2) Self-contained withdrawal records. The registrar export usually has
--    name/email already; storing them on the withdrawal row means we don't
--    have to enrich from the students table at render time.
alter table withdrawals add column if not exists first_name text;
alter table withdrawals add column if not exists last_name  text;
alter table withdrawals add column if not exists email      text;
alter table withdrawals add column if not exists major      text;
alter table withdrawals add column if not exists advisor    text;
alter table withdrawals add column if not exists class_year text;

-- 3) Migrate existing rows with status='Complete' to 'Withdrawn'.
--    Must happen BEFORE the new constraint is added — otherwise the
--    ADD CONSTRAINT step fails because the existing rows would violate it.
update not_returning_reports
set withdrawal_status = 'Withdrawn'
where withdrawal_status = 'Complete';

-- 4) Tighten the check constraint to just the two final values.
alter table not_returning_reports drop constraint if exists not_returning_reports_withdrawal_status_check;
alter table not_returning_reports add constraint not_returning_reports_withdrawal_status_check
  check (withdrawal_status in ('Pending', 'Withdrawn'));
