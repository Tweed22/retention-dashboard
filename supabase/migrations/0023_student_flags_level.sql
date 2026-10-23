-- ─────────────────────────────────────────────────────────────────────────
-- 0023_student_flags_level
-- ─────────────────────────────────────────────────────────────────────────
-- Risk level for leveled tags — currently Midterm Meeting, ranked 1 (lowest)
-- to 4 (highest). Every Midterm Meeting student is higher risk than a
-- non-Midterm student; the level ranks them within that group. Committee
-- members raise a level by clicking the tag, so they need UPDATE.
-- Unleveled tags keep the default 1, which the client ignores.
-- ─────────────────────────────────────────────────────────────────────────

alter table student_flags
  add column if not exists level smallint not null default 1
  check (level between 1 and 4);

drop policy if exists "student_flags_committee_update" on student_flags;
create policy "student_flags_committee_update"
  on student_flags for update to authenticated
  using (public.is_active_committee_member())
  with check (public.is_active_committee_member());

grant update on public.student_flags to authenticated;
