-- 0004 — Add updated_at to not_returning_reports + auto-update trigger.
--
-- WHY: When two NR rows exist for the same student (e.g. a manual entry +
-- an auto-imported withdrawal row), the dashboard's render-time dedupe
-- needs a deterministic way to pick the row most relevant to the user.
-- The previous heuristic (highest field-fullness score) sometimes hid
-- the row Tony had just edited because an older duplicate had more
-- fields populated. Tracking updated_at lets dedupe prefer the row
-- the user touched most recently.
--
-- Safe to re-run: column add is idempotent, trigger drop+create is too.

alter table not_returning_reports
  add column if not exists updated_at timestamptz not null default now();

-- Backfill existing rows so all rows have a value (default only applies
-- to NEW rows; existing rows would otherwise have NULL for the new col,
-- but the NOT NULL + default at column-add time fills them with now()).

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_nrr_set_updated_at on not_returning_reports;
create trigger trg_nrr_set_updated_at
  before update on not_returning_reports
  for each row
  execute function public.set_updated_at();
