-- ─────────────────────────────────────────────────────────────────────────
-- 0021_student_flags
-- ─────────────────────────────────────────────────────────────────────────
-- Informational tags on a student (no effect on any count):
--   'midterm_meeting' — met with the committee at midterm. Per term
--                       (term_id set), so it resets with each new term.
--   'provisional'     — provisional admit. Sticky across terms (term_id null).
-- term_key folds a null term_id into '' so one unique constraint covers
-- both kinds and repeat flagging is idempotent.
-- Committee members may set and clear flags; everyone on the committee reads.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists student_flags (
  id          uuid primary key default gen_random_uuid(),
  student_id  text not null,
  flag        text not null check (flag in ('midterm_meeting', 'provisional')),
  term_id     uuid references terms(id) on delete cascade,
  term_key    text generated always as (coalesce(term_id::text, '')) stored,
  set_by      text,
  created_at  timestamptz not null default now(),
  unique (student_id, flag, term_key)
);

alter table student_flags enable row level security;

drop policy if exists "student_flags_committee_select" on student_flags;
create policy "student_flags_committee_select"
  on student_flags for select to authenticated
  using (public.is_active_committee_member());

drop policy if exists "student_flags_committee_insert" on student_flags;
create policy "student_flags_committee_insert"
  on student_flags for insert to authenticated
  with check (public.is_active_committee_member());

drop policy if exists "student_flags_committee_delete" on student_flags;
create policy "student_flags_committee_delete"
  on student_flags for delete to authenticated
  using (public.is_active_committee_member());

grant select, insert, delete on public.student_flags to authenticated;
grant select, insert, update, delete on public.student_flags to service_role;
