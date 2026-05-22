-- ─────────────────────────────────────────────────────────────────────────
-- 0015_students_manual_status
-- ─────────────────────────────────────────────────────────────────────────
-- Adds an admin-controlled override for a student's registration status,
-- so that committee members investigating a stale or mis-categorized
-- registrar export can force a student to count as "registered" or as
-- "not returning" regardless of what subsequent CSV uploads say. Values:
--   • 'registered'     — force into registeredIds; remove from
--                        Holds/Can Register lists; hide any NR row.
--   • 'not_returning'  — force out of registeredIds; auto-create (or
--                        un-hide) an NR row so the student lives on
--                        the Not Returning tab.
--   • NULL             — no override; CSV data drives the bucket as usual.
--
-- The override persists across CSV uploads — the students table's bulk
-- upsert path (Step 2 of pushDataToSupabase) intentionally does NOT
-- include manual_status in its column list, so the existing value
-- survives. Only the dedicated mark/clear handlers write to this column.
--
-- RLS: students table writes are already admin-gated by migration 0001;
-- no new policy needed.  Tony 2026-05-14.
-- ─────────────────────────────────────────────────────────────────────────

alter table students
  add column if not exists manual_status text
  check (manual_status in ('registered', 'not_returning'));

-- Inherits grants set in migration 0012.
