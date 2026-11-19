-- ─────────────────────────────────────────────────────────────────────────
-- 0025_student_profiles
-- ─────────────────────────────────────────────────────────────────────────
-- Last-known identity/demographics per student that OUTLIVES the daily
-- rosters. The registrar's unregistered/registered CSVs drop a student the
-- day their withdrawal is processed, and each upload deletes `students` rows
-- that aren't on the newest report — so a withdrawn student's class, major,
-- sport, advisor, and email used to vanish from the dashboard (Tony
-- 2026-11-18). Every upload merges what it sees into this table; nothing
-- deletes from it. A blank incoming value never erases a stored one.
-- Admins write (uploads); committee members read.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists student_profiles (
  id           text primary key,
  first_name   text,
  last_name    text,
  email        text,
  major        text,
  advisor      text,
  sports       text[] not null default '{}',
  class_year   text,
  last_seen_at timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table student_profiles enable row level security;

drop policy if exists "student_profiles_committee_select" on student_profiles;
create policy "student_profiles_committee_select"
  on student_profiles for select to authenticated
  using (public.is_active_committee_member());

drop policy if exists "student_profiles_admin_all" on student_profiles;
create policy "student_profiles_admin_all"
  on student_profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on public.student_profiles to authenticated;
grant all on public.student_profiles to service_role;

-- Merge-upsert: incoming non-blank values win, blanks keep what's stored.
-- Sports: a non-empty incoming list replaces the stored one (rosters are the
-- authority while the student is on them); an empty list keeps the old one.
-- security invoker → the caller's RLS applies (admins only can write).
create or replace function public.merge_student_profiles(rows jsonb)
returns integer
language sql
security invoker
set search_path = public
as $$
  with src as (
    select distinct on (r->>'id')
      r->>'id'                              as id,
      nullif(trim(r->>'first_name'), '')    as first_name,
      nullif(trim(r->>'last_name'), '')     as last_name,
      nullif(trim(r->>'email'), '')         as email,
      nullif(trim(r->>'major'), '')         as major,
      nullif(trim(r->>'advisor'), '')       as advisor,
      coalesce(array(select jsonb_array_elements_text(coalesce(r->'sports', '[]'::jsonb))
                     where jsonb_typeof(coalesce(r->'sports', '[]'::jsonb)) = 'array'), '{}') as sports,
      nullif(trim(r->>'class_year'), '')    as class_year
    from jsonb_array_elements(rows) r
    where nullif(trim(r->>'id'), '') is not null
  ), up as (
    insert into student_profiles as p (id, first_name, last_name, email, major, advisor, sports, class_year)
    select id, first_name, last_name, email, major, advisor,
           array(select s from unnest(sports) s where nullif(trim(s), '') is not null), class_year
    from src
    on conflict (id) do update set
      first_name   = coalesce(excluded.first_name, p.first_name),
      last_name    = coalesce(excluded.last_name,  p.last_name),
      email        = coalesce(excluded.email,      p.email),
      major        = coalesce(excluded.major,      p.major),
      advisor      = coalesce(excluded.advisor,    p.advisor),
      sports       = case when cardinality(excluded.sports) > 0 then excluded.sports else p.sports end,
      class_year   = coalesce(excluded.class_year, p.class_year),
      last_seen_at = now(),
      updated_at   = now()
    returning 1
  )
  select count(*)::int from up;
$$;

grant execute on function public.merge_student_profiles(jsonb) to authenticated;

-- Backfill from everything we still have: current students rows first, then
-- fill blanks from the term listing, Not Returning rows, and withdrawals.
insert into student_profiles (id, first_name, last_name, email, major, advisor, sports, class_year)
select id, nullif(first_name,''), nullif(last_name,''), nullif(email,''), nullif(major,''),
       nullif(advisor,''), coalesce(sports, '{}'), nullif(class_year,'')
from students
on conflict (id) do nothing;

insert into student_profiles (id, first_name, last_name, major, class_year)
select distinct on (student_id) student_id, nullif(first_name,''), nullif(last_name,''), nullif(major,''), nullif(class_cde,'')
from term_cohort order by student_id, uploaded_at desc nulls last
on conflict (id) do update set
  first_name = coalesce(student_profiles.first_name, excluded.first_name),
  last_name  = coalesce(student_profiles.last_name,  excluded.last_name),
  major      = coalesce(student_profiles.major,      excluded.major),
  class_year = coalesce(student_profiles.class_year, excluded.class_year);

insert into student_profiles (id, major, class_year, sports)
select distinct on (student_id) student_id, nullif(major,''), nullif(class_year,''),
       coalesce(array(select trim(s) from unnest(string_to_array(coalesce(sport,''), ',')) s where trim(s) <> ''), '{}')
from not_returning_reports where student_id is not null and student_id <> ''
order by student_id, (sport is not null and sport <> '') desc, updated_at desc
on conflict (id) do update set
  major      = coalesce(student_profiles.major,      excluded.major),
  class_year = coalesce(student_profiles.class_year, excluded.class_year),
  sports     = case when cardinality(student_profiles.sports) > 0 then student_profiles.sports else excluded.sports end;

insert into student_profiles (id, first_name, last_name, email, major, advisor, class_year)
select distinct on (student_id) student_id, nullif(first_name,''), nullif(last_name,''), nullif(email,''),
       nullif(major,''), nullif(advisor,''), nullif(class_year,'')
from withdrawals where student_id is not null and student_id <> ''
order by student_id, last_active_date desc nulls last
on conflict (id) do update set
  first_name = coalesce(student_profiles.first_name, excluded.first_name),
  last_name  = coalesce(student_profiles.last_name,  excluded.last_name),
  email      = coalesce(student_profiles.email,      excluded.email),
  major      = coalesce(student_profiles.major,      excluded.major),
  advisor    = coalesce(student_profiles.advisor,    excluded.advisor),
  class_year = coalesce(student_profiles.class_year, excluded.class_year);
