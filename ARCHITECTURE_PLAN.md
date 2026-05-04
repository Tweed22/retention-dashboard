# Retention Dashboard — Hosted Multi-User Architecture Plan

**Status:** Draft for review
**Date:** 2026-04-30

This document plans the move from the current single-user, browser-only `retention-dashboard.html` (where each viewer drops their own CSVs and data lives in their `localStorage`) to a hosted dashboard where Tony uploads CSVs once and any visitor can view, submit risk scores, and flag students who aren't returning.

---

## 1. What's changing

| | Today | Target |
|---|---|---|
| Data location | Browser memory + `localStorage` (per-viewer) | Central database |
| Who uploads CSVs | Each viewer | Only Tony (admin) |
| Who sees the data | Whoever loaded it locally | Anyone with the dashboard link |
| Risk scores | None | Auto-calculated, with user override |
| Not Returning list | Per-viewer, lives in `localStorage` | Shared, viewable by retention committee |
| Submissions | None | Retention committee members can submit risk overrides + non-returner reports |
| Withdrawals | Not tracked | CSV upload of completed withdrawals; current-term-only view + auto-fed into Not Returning |
| Audience | Whoever loads the file | Retention committee only (small, trusted group) |

The visual breakdown work (KPI cards, donut, bar chart, hold cards, filters) is mostly done in the existing HTML — that UI carries over. The architecture work is mainly **(a) replacing CSV upload with a server fetch**, **(b) adding write endpoints for submissions**, and **(c) adding the risk-score column everywhere students appear**.

---

## 2. Recommended stack

You picked "plan first, no backend chosen." Here's the comparison and my recommendation.

### Recommendation: **Supabase** (Postgres + auth + auto-generated REST/realtime APIs)

**Why:**
- **Admin-only write access works cleanly.** You log in (Google SSO or magic link), gain CSV upload rights via Row-Level Security (RLS). Visitors hit the same site without logging in and can read + submit through scoped anon policies.
- **Concurrent submissions.** Multiple advisors flagging non-returners at once will work without the lock contention/quirks Google Sheets has.
- **Real-time updates.** When someone submits a non-returner, every other open dashboard sees it within ~1s without a refresh. This is a nice-to-have but matches the "viewable by all visitors" requirement.
- **Free tier covers the scale.** Few thousand students × tens of viewers = nowhere near the limits.
- **Postgres SQL.** Joining holds × students × risk overrides is trivial; same query in Sheets is painful.

**Where it hurts:** student data on a third-party SaaS may need a Data Processing Agreement with your institution. See FERPA section.

### Alternatives considered

- **Google Sheets backend** — appealing for simplicity (you'd paste CSVs into tabs, the page reads via the Sheets API). But concurrent writes to the same row break, there's no real auth model for the "anon submitter" pattern (you'd be exposing a write-enabled API key in the page), and the dashboard's join-heavy logic gets ugly. Pass.
- **Self-hosted on college servers** — best for compliance, but I don't know what your IT supports. If your institution already has a hosting environment + SSO available, this is the right answer long-term. Worth a 15-minute call with IT before committing to Supabase.

### Hosting for the front-end
The HTML page itself is static — any of GitHub Pages, Netlify, Vercel, or Cloudflare Pages work. Free, fast deploys from a Git repo. **Cloudflare Pages** is my pick (fastest globally, generous free tier, no egress fees if we ever pull data through a worker).

---

## 3. FERPA / data sensitivity

Tony confirmed that institutional clearance for third-party processors is in place — Supabase + Cloudflare are acceptable.

### Tiered access model (revised 2026-05-04 for hosting)

The audience is no longer uniform — Tony asked for a public-facing Summary so anyone can see aggregate retention numbers (e.g., projected onto a screen at a board meeting), while the detail tabs that contain student-level PII stay gated. This changes the FERPA picture meaningfully and brings auth forward from Phase 5 to Phase 1.

| Surface | Audience | Auth | Contents |
|---|---|---|---|
| **Summary tab** | Public (anyone with the URL) | None | Aggregate counts, percentages, donuts, Reasons-Not-Returning chart. No PII, no per-student data. |
| **Holds Breakdown / Can Register / New Students / Withdrawals / Not Returning** | Retention committee allowlist | Magic-link email (Supabase Auth) | Full per-student rows with names, IDs, emails, holds, advisors. |
| **NR submission form** | Authenticated committee only | Magic-link email | Form lives on the gated Not Returning tab; submitter is auto-attributed via the auth user record. |
| **CSV exports** | Authenticated committee only | Magic-link email | Both "Download visible" and "Download all" buttons. Files contain PII so distribution is the committee's responsibility once downloaded — see warning banner below. |
| **Admin upload** | Tony only | Same auth, admin role | Drop the four CSVs (unreg, reg, new, withdrawals); pushes to Supabase. |

### Small-cell suppression on the public Summary

The Summary page is generally safe — counts of "Total Returning" or "Registered Rate" don't identify anyone. But two specific widgets can leak at small numbers:

- **Reasons Not Returning chart.** If a small school has only one student in a sensitive bucket (Suspension, Medical), the chart could effectively re-identify them to colleagues. Mitigation: suppress any reason bar with count < 5 on the public view (committee view shows the real number). The threshold is configurable in the Settings panel; n=5 is the standard FERPA-aligned cutoff.
- **Per-hold donuts.** "1 student with Immunization Hold, 0 likely returning" is identifying at small enrollments. Same n<5 suppression rule applies — render the donut with a "<5" label instead of the exact count.

The split is enforced server-side via Supabase Row-Level Security so a malicious anon client cannot bypass it by hand-crafting requests.

### Magic-link auth allowlist

Committee email addresses are stored in a `committee_members` table; Supabase Auth's email magic-link flow accepts only allowlisted addresses. Adding/removing members is done through the admin Settings panel. This replaces the original "shared-secret UUID URL" approach because access is no longer uniform — we need to differentiate Tony from committee members from the public.

---

## 4. Data model

### Existing CSV inputs (from `retention-dashboard.html`)

The current page reads three CSVs and the parser is forgiving on column names. Here's what it expects:

**Unregistered Students CSV** (the main source of returning-student records):
- `ID` (or `id#`, `student id`, `sid`)
- `First Name` / `Last Name` (or single `Name` column)
- `Email`
- `Major` / `Program` / `Degree`
- `Advisor` / `Adviser` / `Counselor`
- `Sport` / `Team` / `Athletics` (multi-value, separated by `,;|`)
- `Class` / `Year` / `Classification` (Freshman/Sophomore/Junior/Senior)
- `Hold_1` … `Hold_6` (or single `Holds` column)

**Registered Students CSV** — only `ID` matters; used to mark which students have ≥1 enrollment.

**New Students CSV** — same shape as Unregistered; processed separately so they don't dilute the returning-rate metric.

**Withdrawal Students CSV** (added 2026-05-04) — uploaded separately from the three above, on its own cadence as withdrawals are processed. Expected columns (parser will be flexible on header naming, like the other CSVs):
- `ID` (or `id#`, `student id`, `sid`) — required, used to match against `students`
- `Last Active Date` (or `LDA`, `last date of attendance`, `last attended`) — **required and authoritative**; this is the field used for the current-term filter, NOT the date the withdrawal was processed
- `Withdrawal Processed Date` (or `processed date`, `withdrawal date`) — captured as metadata; not used for filtering
- `Withdrawal Reason` / `Withdrawal Type` — captured and mapped to the NR `reason` vocabulary (Medical, Academics – Performance, Suspension, etc.). Unrecognized values land in the row's reason field as a custom string and surface as a "(custom)" bar on the Reasons chart, identical to how typed Other reasons work today.

Only rows where `last_active_date ∈ [current_term.start_date, next_term.start_date)` are surfaced in the Withdrawals tab and auto-fed into Not Returning. Withdrawals with a last active date in a previous term are stored but hidden from the current view; the Withdrawals tab will have a term selector to inspect prior terms.

**Five recognized blocking holds:** Advising, Account, Registrar Office, Missing Documents, Immunization.

### New database tables (Supabase / Postgres)

```sql
-- Uploaded snapshot of each student. One row per student.
-- Re-populated each time Tony uploads CSVs.
students (
  id              text primary key,    -- Student ID from CSV
  first_name      text,
  last_name       text,
  email           text,
  major           text,
  advisor         text,
  sports          text[],              -- multi-value; matches existing parser
  class_year      text,                -- 'Freshman' | 'Sophomore' | ...
  holds           text[],              -- raw hold strings; ['Advising Hold', ...]
  is_new_student  boolean,             -- from new students CSV
  is_registered   boolean,             -- ID appeared in registered CSV
  snapshot_id     uuid,                -- foreign key to upload batch
  updated_at      timestamptz
);

-- Each CSV upload creates one snapshot. Lets us roll back, audit changes,
-- and know "data as of when".
csv_snapshots (
  id              uuid primary key,
  uploaded_by     uuid,                -- Tony's auth user id
  uploaded_at     timestamptz,
  source_files    jsonb,               -- {unreg: 'foo.csv', reg: '...', new: '...', withdrawals: '...'} — any subset present
  student_count   int,
  notes           text                 -- optional free text
);

-- User-submitted risk scores. Multiple users can score the same student.
risk_overrides (
  id              uuid primary key,
  student_id      text references students(id),
  score           int,                 -- 0-100
  category        text,                -- 'Low'|'Moderate'|'High'|'Critical'
  rationale       text,
  submitter_name  text,                -- typed at submission time
  submitter_email text,                -- optional, for follow-up
  created_at      timestamptz,
  is_hidden       boolean default false  -- soft delete (admin can hide spam)
);

-- Annotated events on the timeline: registration windows opening,
-- outreach campaigns, deadlines, etc. Used to draw vertical markers
-- on trend charts and to give context to spikes/dips.
timeline_events (
  id              uuid primary key,
  event_date      date not null,       -- when the event happened (or starts)
  end_date        date,                -- optional — for ranges like "registration window"
  category        text,                -- 'Registration'|'Outreach'|'Deadline'|'Communication'|'Other'
  source_office   text,                -- 'Registrar'|'Advising'|'Financial Aid'|'Athletics'|...
  title           text not null,       -- short label shown on the chart
  description     text,                -- optional longer detail
  color           text,                -- optional hex; otherwise category default
  created_by      uuid,                -- admin user id
  created_at      timestamptz
);

-- "I heard X isn't coming back." Maps to the existing nrList structure.
not_returning_reports (
  id                 uuid primary key,
  student_id         text,             -- nullable: submitter may only have a name
  student_name       text,
  reason             text,             -- one of NR_REASONS or a custom string typed via Other → text-input swap
  withdrawal_status  text,             -- 'Pending' | 'Complete'
  notes              text,
  submitter_name     text,
  submitter_email    text,
  source_withdrawal_id uuid,           -- nullable; points at withdrawals.id when this row was auto-created from a withdrawal CSV import. Lets us idempotently re-sync without dupes.
  created_at         timestamptz,
  is_hidden          boolean default false
);

-- Allowlist of email addresses permitted to receive a magic-link login.
-- Added 2026-05-04 when the gated/public split made real auth necessary.
-- Tony manages this list through the admin Settings panel.
committee_members (
  id              uuid primary key,
  email           text not null unique,
  display_name    text,                  -- shown next to NR submissions etc.
  role            text not null default 'member',  -- 'admin' (Tony) | 'member'
  added_by        uuid,
  added_at        timestamptz,
  is_active       boolean default true   -- soft-disable instead of delete so audit trail survives
);

-- Academic terms. Replaces the single "semester start date" Setting from the
-- pre-2026-05-04 plan. Admin maintains this list; "current term" is computed
-- as the row whose start_date is the most recent ≤ today, and the term window
-- is [current.start_date, next.start_date) where next = the term with the
-- smallest start_date strictly greater than current's. If no next term exists
-- yet, the upper bound is open-ended (today).
terms (
  id              uuid primary key,
  name            text not null,           -- e.g. 'Spring 2026', 'Fall 2026'
  start_date      date not null unique,
  notes           text,
  created_by      uuid,
  created_at      timestamptz
);

-- Authoritative completed withdrawals, sourced from the registrar's CSV.
-- Re-uploads upsert by (student_id, last_active_date); duplicates collapse.
withdrawals (
  id                 uuid primary key,
  student_id         text references students(id),
  last_active_date   date not null,        -- the field used for the term filter
  processed_date     date,                  -- when the registrar processed it (metadata only)
  withdrawal_reason  text,                  -- mapped from CSV; matches NR_REASONS where possible, else stored verbatim
  withdrawal_type    text,                  -- optional, e.g. 'Official', 'Administrative'
  term_id            uuid references terms(id),  -- denormalized at upload time for fast filtering
  snapshot_id        uuid references csv_snapshots(id),  -- which CSV upload introduced this row
  source_filename    text,
  created_at         timestamptz,
  unique (student_id, last_active_date)
);
```

**Auto-sync rule:** when a `withdrawals` row is inserted (or upserted) and its `term_id` matches the current term, the upload step also upserts a corresponding `not_returning_reports` row with `withdrawal_status = 'Complete'`, `submitter_name = '[CSV import]'`, `reason = withdrawal_reason` (or the mapped vocabulary value), and `source_withdrawal_id = withdrawals.id`. The `source_withdrawal_id` foreign key makes this idempotent — re-uploading the same withdrawal CSV will not create duplicate NR rows. If a human committee member already added an NR row for that student, the import does NOT overwrite or merge — it inserts a separate row tagged as the CSV-sourced version, and the moderation UI on the Not Returning tab lets the admin reconcile (hide one, keep the other).

### RLS / access policies (sketch)

RLS reflects the tiered model from section 3 — public can read aggregates only; per-student rows require committee auth; writes require admin.

- `snapshot_metrics`: **SELECT for anon** (this is the only table the public Summary reads). INSERT/UPDATE admin-only. The metrics row is computed at upload time so the public never sees per-student data.
- `students`, `withdrawals`, `not_returning_reports`, `risk_overrides`: SELECT only for `auth.role() = 'authenticated'` AND the user's email is in `committee_members` with `is_active = true`. INSERT for committee on submission tables (`risk_overrides`, `not_returning_reports`); admin-only for the rest. UPDATE/DELETE admin-only across the board — we don't let submitters edit/delete their own rows because that invites disputes.
- `csv_snapshots`, `timeline_events`, `terms`, `committee_members`: SELECT for committee, INSERT/UPDATE/DELETE admin-only — institutional records.

The RLS policies are defined in the Supabase migration file (`/supabase/migrations/0001_init.sql` in the repo) so they're version-controlled alongside the schema.

---

## 5. Risk score methodology

You picked **auto-calculated + user override**. Here's the proposed formula and how the two combine.

### Auto score (0–100)

Computed at render time from `students` + `not_returning_reports` data:

| Signal | Points |
|---|---|
| Has any blocking hold | +30 |
| Each additional blocking hold beyond the first | +10 |
| Not yet registered AND registration window has opened (week 9 of semester) | +20 |
| Class year = Freshman or Sophomore | +15 (national attrition data — more applies to underclassmen) |
| Has at least one non-returner report against them | +25 |
| At least one non-returner report with `withdrawal_status = Complete` | +50 (pegs to ≥50) |
| `is_new_student = true` | reduce final by 10 (new students lack a returning-rate signal; treat conservatively) |

Registration officially opens **week 9 of the semester**. The dashboard will compute the current semester week from the current term's `start_date` in the `terms` table (admin-maintained — same Settings panel that drives the withdrawal current-term filter) and only apply the +20 unregistered penalty once we're past week 9. Before week 9, "not yet registered" is normal and shouldn't inflate risk.

Final score is clamped to [0, 100], then bucketed:

- **0–24 Low** (green)
- **25–49 Moderate** (amber)
- **50–74 High** (orange)
- **75–100 Critical** (red)

### User override

When a user submits a risk score, they're saying "I disagree with the auto score" or "I have info the data doesn't show." The dashboard shows:

- **Auto score** (always computed, always shown)
- **User-submitted score** — if any submissions exist, show the **average** of all non-hidden submissions, plus a count and the latest rationale. Hovering or clicking expands to the full submission list.
- **Effective score** (used for sort/filter in tables) = the user-submitted average if any submissions exist, otherwise the auto score. We pick the user input over the model when humans have weighed in, but never throw away the auto signal.

Submission form fields: score (slider 0-100), category (auto-fills from score, can override), rationale (required, ≥10 chars), submitter name (required), submitter email (optional).

**Spam mitigation:** not needed at this scale. The audience is the retention committee only and the URL is a shared secret; we'd be adding friction for no benefit. If/when access expands, add Cloudflare Turnstile and per-IP rate limits in the Phase 5 hardening pass.

---

## 6. Historical trends & event markers

You want to track habits over time and mark contextual events (registration opens, outreach campaigns, etc.). The `csv_snapshots` table already gives us the time series for free — every upload is a snapshot, so we can replay how the numbers moved between any two dates. The new `timeline_events` table captures the "why" alongside the "what."

### What we track over time

For each snapshot, we derive and store these aggregate metrics (so trend queries don't have to re-scan all student rows):

```sql
snapshot_metrics (
  snapshot_id     uuid primary key references csv_snapshots(id),
  total_returning int,
  total_registered int,
  registration_rate numeric,        -- % of returning students registered
  total_new       int,
  new_registered  int,
  total_holds     int,
  holds_advising  int,
  holds_account   int,
  holds_registrar int,
  holds_missing_docs int,
  holds_immunization int,
  can_register    int,
  not_returning_count int,           -- count of non-hidden NR reports at this snapshot
  high_risk_count int,               -- students with effective risk ≥50
  critical_risk_count int,           -- effective risk ≥75
  -- breakdowns for sliceable trend views:
  by_class_year   jsonb,             -- {Freshman: {total, registered}, ...}
  by_advisor      jsonb,
  by_major        jsonb,
  by_sport        jsonb,
  computed_at     timestamptz
);
```

Computing these on upload is fast (<1s for a few thousand students) and means trend pages render instantly without re-aggregating.

### New "Trends" tab in the UI

A new top-level nav tab between **Summary** and **Holds Breakdown**. Contents:

- **Headline line chart** — registration rate, returning total, hold counts, and risk counts over time. Toggle metrics on/off via the legend. X-axis = snapshot date.
- **Vertical event markers** — every `timeline_events` row draws a vertical line (or shaded band, for date ranges like a registration window) on the chart, color-coded by category, labeled at the top. Hover shows full detail. Clicking opens an edit panel (admin) or detail panel (viewer).
- **Slice selector** — "All students" / "By class year" / "By advisor" / "By major" / "By sport." Switches the chart to small-multiples or a stacked view, pulling from the relevant `by_*` JSON breakdown.
- **Date range picker** — default last 90 days; expandable to "this term," "year-to-date," "all time."
- **Comparison mode (Phase 4)** — overlay last year's curve at the same point in their cycle. Powerful for "are we ahead or behind compared to last year?" but needs a second term of data before it's useful.

### Event entry (admin-only)

Small form on the Trends tab (visible only to admin):
- Date (required), end date (optional)
- Category (Registration / Outreach / Deadline / Communication / Other)
- Source office (Registrar / Advising / Financial Aid / Athletics / Custom)
- Title (required, short — appears on the chart)
- Description (optional, shown on hover/click)

Categories are color-coded so the timeline visually distinguishes "registration opened" (green) from "advising outreach sent" (blue) from "withdrawal deadline" (red).

### Handling daily-multiple-times upload cadence

Tony will be uploading several times per day during the registration push. That's potentially 4–5 snapshots/day × ~12 weeks ≈ 400–500 snapshots before the semester even starts. Storage isn't the issue (cheap), but the trend chart would become unreadable if every snapshot drew its own datapoint.

Approach:

- **Storage:** keep every snapshot. They're cheap and the audit value is real ("what did the dashboard say at 9am vs 3pm on the day we sent the outreach email?").
- **Default chart granularity:** **latest snapshot per day**. The trend line draws one point per day, using the most recent upload's metrics. This matches how a viewer thinks about the data — "where did we end the day?" — and produces a clean readable chart.
- **Granularity toggle:** dropdown for `Daily (latest)` / `Daily (earliest)` / `All snapshots` / `Hourly average`. Power users can switch when they want to see intra-day movement around an event (e.g., did registrations spike right after the outreach email?).
- **Snapshot dedup:** if two consecutive uploads produce identical metrics, we still keep both rows (audit) but the trend query collapses them. Cheap.

### Backfill importer for older data

Tony has limited older Excel spreadsheets with basic tracking. Phase 3 will include a small **manual backfill form** in the admin UI:

- Pick a date
- Enter aggregate numbers manually (total returning, total registered, total holds by type, etc.)
- Saves as a `csv_snapshots` row with `notes = 'Backfilled from historical spreadsheet'` and a corresponding `snapshot_metrics` row

This way, even rough historical data points populate the trend chart so it's not empty on launch. The form mirrors `snapshot_metrics` columns; missing fields are stored as null and skipped from per-metric chart series rather than rendered as zero.

### Snapshot retention

Keep all snapshots indefinitely — disk is cheap, and this data has long-term institutional value (e.g., "what did our 4th-week registration look like in 2024 vs 2025?"). Only the snapshot's aggregate metrics row is needed for trend rendering; the full per-student snapshot rows can stay too, and we can add a "view dashboard as of [date]" mode later if you want to inspect any historical state.

---

## 7. UI changes from the current page

The existing tabs (Summary, Holds Breakdown, Can Register, New Students, Not Returning) all stay. New **Trends** (section 6) and **Withdrawals** (below) tabs are added. Per-tab additions:

- **Header:** "⬆ Update Data" button only visible when logged in as admin. Replace the "🔒 Private — data stays in your browser" badge with "Last updated: [date], by Tony" pulled from `csv_snapshots`. Add a "Sign in" button (right side) for unauthenticated visitors; it opens a magic-link email modal. Once signed in, swap to "Signed in as [name] · Sign out".
- **Tab visibility:** unauthenticated visitors see only the Summary tab (other tabs are hidden, not just disabled). Once signed in as a committee member, all tabs appear. The admin role additionally exposes the Update Data button and the Settings panel.
- **CSV export buttons:** every gated tab (Holds Breakdown, Can Register, New Students, Withdrawals, Not Returning) gets a small button cluster top-right of the table: `Download visible (.csv)` and `Download all (.csv)`. Files are named like `holds-2026-05-04.csv`. The export is client-side — the rows are already in browser memory so no server round-trip needed. A red banner reminds the user that exported files contain student PII and should only be shared via institution-approved channels.
- **Summary:** add a 6th KPI card "Critical Risk" with count of students at score ≥75. Add a small "Risk Distribution" donut alongside the existing "Registration Status" donut. Add a 7th KPI card "Withdrawn This Term" sourced from `withdrawals` filtered to the current term.
- **Holds Breakdown / Can Register / New Students tables:** new column "Risk" showing effective score + colored category badge. Sortable. New filter dropdown for risk category alongside the existing major/advisor/sport/class filters.
- **Student detail (new):** clicking any student row opens a side panel showing all their fields, the auto-score breakdown (which signals fired), all risk submissions for that student, all non-returner reports, all withdrawal records (if any), and a "Submit Risk Score" form.
- **Not Returning:** the existing add-row UI works — back it with `not_returning_reports` instead of `localStorage`. Show submitter name beside each row. Admin-only "Hide" button replaces the existing "Remove" (since deletion is admin-only now). Rows auto-created from a withdrawal CSV import are tagged with a small "From withdrawal CSV" chip and link to the source row in the Withdrawals tab.
- **Withdrawals (new):** lists every `withdrawals` row whose `last_active_date` falls inside the current term window. Columns: ID · Name · Last Active Date · Processed Date · Reason · Type · Major · Advisor · Class Year. Sortable on every column; default sort is `last_active_date` descending. Filter dropdowns for class year, advisor, major, and reason. A small term selector at the top defaults to the current term but lets viewers switch to prior terms for retrospective comparisons. KPI strip across the top: total withdrawals this term, withdrawals by class year, top reason, count flagged via this CSV that already had a human NR entry (so the admin sees overlap that may need reconciliation). Admin-only "Re-import withdrawals CSV" button at the top right. The auto-NR-sync runs on every import; viewers see no separate sync action.

The class-year filter (Freshman/Sophomore/Junior/Senior) you mentioned isn't currently in the UI — we'll add it as a filter on the Holds Breakdown, Can Register, and New Students tables. The CSV parser already captures `classYear`, so no upload-format change is needed.

---

## 8. Phased build plan

I'd ship this in four phases so you get value fast and we don't bet everything on the final design before seeing it run.

### Phase 1 — Hosted backend + auth + public/private split (≈3–4 sessions)
This phase is bigger than originally scoped because the hosted-model decision (2026-05-04) folds in what was previously Phase 5 auth and Appendix C CSV export.

- **Supabase setup**: create project, define schema above (including `csv_snapshots`, `snapshot_metrics`, `terms`, `withdrawals`, `committee_members`), commit migration as `supabase/migrations/0001_init.sql`. RLS policies enforce the tiered access model from section 3.
- **Auth**: enable Supabase magic-link email auth. Allowlist enforced by the `committee_members` table and an RLS policy on every committee-readable table. Tony's email seeded as `role='admin'`.
- **Admin upload page** (`/admin`, admin-only): drag-drop the **four** CSVs — unregistered, registered, new, withdrawals — push to `students` + `csv_snapshots` + `withdrawals` + computed `snapshot_metrics`. Withdrawals upload runs the auto-sync rule (insert/upsert NR rows for current-term withdrawals). Seed `terms` with current + next term so the filter has both bounds.
- **Public Summary** (`/`, no auth): renders aggregate widgets from `snapshot_metrics`. Small-cell suppression (n<5) applied to Reasons-Not-Returning and per-hold donuts.
- **Gated detail tabs** (`/dashboard`, committee auth required): the existing Holds Breakdown / Can Register / New Students / Withdrawals / Not Returning tabs, reading from `students` + `withdrawals` + `not_returning_reports`. Admin-only Settings panel exposes the `terms` and `committee_members` lists.
- **NR submission**: form lives on the gated Not Returning tab. Submitter is auto-attributed via `auth.uid()` joined to `committee_members.display_name`.
- **CSV export**: per-tab "Download visible" + "Download all" buttons on every gated tab. Client-side; PII warning banner above the buttons.
- **Real-time**: Supabase realtime subscription on `csv_snapshots` so an open viewer updates within ~1s of a new upload — useful when Tony pushes a fresh CSV mid-meeting.
- **Frontend deploy**: Cloudflare Pages connected to a Git repo (Tony provides). Environment variables (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) configured in the Pages dashboard.

**End state of Phase 1:** the dashboard is live at a public URL. The Summary page is accessible to anyone; everything else is gated behind magic-link auth restricted to the committee allowlist. CSV export, real-time updates, and the auto-NR-sync from withdrawal uploads all work. No risk scoring yet, no Trends tab yet.

### Phase 2 — Risk scoring + filters (≈1 session)
- Auto-score formula + risk badges in all tables
- Risk category filter, class-year filter
- Student detail side panel
- Risk submission form

### Phase 3 — Trends + event markers (≈1 session)
- Trends tab with line chart over snapshots
- `timeline_events` table + admin event entry form
- Event markers (vertical lines / shaded bands) on the chart
- Slice selector (all / class year / advisor / major / sport)
- Date range picker

### Phase 4 — Polish (≈1 session)
- "Last updated by" provenance on every screen
- Admin moderation tools (hide spam submissions, edit/correct events, manage backfill entries)
- Audit log for admin actions
- Settings panel: `terms` list management (add/edit term names + start dates; drives the week-9 risk calc and the withdrawal current-term filter)
- Year-over-year comparison overlay (once a second term of data exists — won't be useful at first launch)

### Phase 5 — Hardening (only if/when access broadens beyond the current model)
Most of what was originally in this phase moved to Phase 1 once the hosted model was decided. What's left here triggers only if Tony decides to widen the audience further (e.g., open NR submission to faculty, or expose detail tabs beyond the committee).
- Cloudflare Turnstile on the NR submission form (currently committee-only — not needed)
- Rate limits on anon reads of `snapshot_metrics` (DDoS guardrail; only needed if the URL goes viral)
- College SSO migration if magic-link proves cumbersome for committee members
- Audit log queryable by department admins (currently admin-only)

---

## 9. Decisions confirmed (2026-04-30)

| # | Decision | Notes |
|---|---|---|
| 1 | **Auth gating deferred** | Build first, gate later. Audience is retention committee only; URL is a shared-secret UUID path. Phase 5 (not currently scheduled) adds a real auth gate when access expands. |
| 2 | **Third-party processors approved** | Supabase + Cloudflare Pages cleared for student data. |
| 3 | **Registration opens week 9 of semester** | Drives the +20 "not yet registered" risk signal. Current term's `start_date` (from the `terms` table) is admin-editable in a Settings panel so the calc adapts each term. |
| 4 | **Submitter attribution = typed name** | Trusted small group; no need for verified identity at this stage. Optional email field for follow-up. |
| 5 | **CSV cadence: multiple times daily** | Through registration window up to start of semester. Drives the trend-chart granularity decisions in section 6. |
| 6 | **Keep multi-term history** | Snapshots retained indefinitely. Year-over-year overlay becomes useful once we have a second term of data. |
| 7 | **Audience = retention committee only** | Small, trusted group. Confirms why auth can be deferred. |
| 8 | **Proposed event categories accepted** | Registration / Outreach / Deadline / Communication / Other; offices: Registrar / Advising / Financial Aid / Athletics / Custom. |
| 9 | **Backfill: limited, best-effort** | Older Excel spreadsheets have basic tracking info. Phase 3 will include a manual backfill form so historical data points can be hand-entered into `snapshot_metrics`. Tony will collect what's available before then. |

### Addendum — 2026-05-04: Withdrawal CSV ingestion

| # | Decision | Notes |
|---|---|---|
| 10 | **4th CSV input: withdrawals** | Uploaded separately from the three existing CSVs, on its own cadence as the registrar processes withdrawals. Filtered to current term using `last_active_date`, **not** the date the withdrawal was processed. |
| 11 | **Term boundaries from `terms` table** | "Current term" = the term whose `start_date` is the most recent ≤ today. Window is `[current.start_date, next.start_date)`. If no next term row exists yet, upper bound is open-ended (today). Replaces the single "semester start date" Setting. |
| 12 | **New Withdrawals tab + auto-add to NR** | A new top-level tab lists current-term withdrawals; each row also auto-creates a `not_returning_reports` row tagged `submitter_name = '[CSV import]'` and linked back via `source_withdrawal_id` for idempotent re-imports. Human-entered NR rows are NOT overwritten — admin reconciles manually. |
| 13 | **CSV columns: ID + LDA + processed date + reason/type** | All four. Parser will be flexible on header names like the existing parsers. Reason maps to NR_REASONS where possible; unmapped values land verbatim and surface as "(custom)" reasons on the chart. |

### Addendum — 2026-05-04: Hosting model

| # | Decision | Notes |
|---|---|---|
| 14 | **Public Summary, gated everything else** | The Summary tab renders to anonymous visitors (aggregate counts only). Holds Breakdown, Can Register, New Students, Withdrawals, and Not Returning are gated behind committee auth because they contain per-student PII. Enforced via Supabase RLS so the split can't be bypassed client-side. |
| 15 | **Magic-link email auth, committee allowlist** | Replaces the original "shared-secret UUID URL" approach. Committee email addresses live in a new `committee_members` table; Supabase Auth's email magic-link flow accepts only allowlisted addresses. Admin role flag on Tony's row. Brings auth forward from the previously-deferred Phase 5 into Phase 1. |
| 16 | **NR submission stays committee-only** | Form lives on the gated Not Returning tab; submitter is auto-attributed via `auth.uid()` joined to `committee_members.display_name`. The public Summary does not have a submission form. Avoids spam and maintains submitter accountability. |
| 17 | **Per-tab CSV export: visible + all** | Two buttons per gated tab — "Download visible" exports the current filtered/sorted view; "Download all" exports the full unfiltered dataset for that tab. Files are named `<tab>-YYYY-MM-DD.csv`. PII warning banner on the gated tabs reminds the user that exported files contain student data and should be shared only via institution-approved channels. |
| 18 | **Small-cell suppression on public Summary** | Reasons-Not-Returning bars and per-hold donuts on the public Summary suppress counts < 5 (rendered as "<5"). The committee view shows real counts. Standard FERPA-aligned threshold; configurable in admin Settings. |
| 19 | **Real-time updates via Supabase subscription** | An open dashboard refreshes within ~1s of a new CSV upload — useful when Tony pushes fresh data mid-meeting. Implemented as a `csv_snapshots` realtime subscription that re-fetches `snapshot_metrics` (and per-tab data, for authed clients) on insert. |

**Phase 1 is now ready to execute.** Tony's TODO before code starts: (a) sign up for a Supabase project, (b) sign up for a Cloudflare Pages account, (c) provide a Git repo to deploy from. See `DEPLOYMENT.md` (separate file) for the step-by-step.

---

## Appendix A — Existing data that carries over without change

The current parser already handles flexible column naming, deduplicates registered IDs, merges multi-sport athletes, and excludes new students from the unregistered set. Phase 1 should reuse `parseCSV`, `parseCSVRow`, `findField`, and `normalizeStudent` verbatim — they're solid and battle-tested against your real CSVs. The change is just where the data goes after parsing (Supabase rather than in-memory).

## Appendix B — UI changes already applied to retention-dashboard.html

These tweaks were applied directly to the standalone HTML on 2026-04-30 and should carry over to the hosted version:

1. **Per-hold donuts replace the holds bar chart on Summary.** Five small SVG donuts, one per hold type (Advising / Account / Registrar Office / Missing Docs / Immunization). Center number = students still likely returning, smaller number below = total with that hold, ring shows the not-returning slice in red.
2. **Edit button on Not Returning rows.** Each row now has both Edit and Remove. Edit swaps the row into inline inputs; Save commits, Cancel discards. Re-evaluates the registered-for-courses status on save.
3. **Not Returning fallback to registered CSV.** When adding a row, if the ID isn't in the unregistered or new CSVs we now look it up in the registered CSV. Same for name-based lookup when no ID is given. If matched there, the row is tagged "Registered for Courses" and a fourth KPI ("Registered for Courses") on the NR page surfaces the count.
4. **Reconciliation.** `isNRRegistered()` re-checks every row against the current `registeredIds` set on each render and on every CSV upload, so an existing NR entry will flip to "Registered for Courses" automatically the moment a new registered CSV brings them in.
5. **All emojis/icons removed.** Header, drop zones, empty states, KPI subtitles, hold cards, table action buttons. Plain text labels throughout.
6. **Returning Student Status split into 3 donuts.** Same SVG style as the holds grid. Each donut shows count in center, % of total returning below — no more single Chart.js doughnut. Chart.js dependency dropped entirely.
7. **Reasons Not Returning bar chart on Summary.** Horizontal bars sorted by count. A row with multiple reasons contributes to each, so the chart shows total *reasons cited*, not student headcount. Stays empty with a placeholder message until NR data exists.
8. **Reasons list updated.** Renamed "Academic dismissal" → "Suspension"; consolidated "Medical / health reasons" → "Medical"; added Academics - Major, Academics - Performance, Faculty, Athletic, Conflict with Faculty and/or Staff, Housing. 13 total reasons. Legacy `localStorage` rows migrate automatically on load.
9. **Single reason with inline editing + Other → custom text.** Reverted from the multi-select experiment. `reason` is a single string field again. The reason cell on each NR row is a dropdown directly — no need to enter Edit mode. Picking "Other" swaps the dropdown for a text input where a custom reason can be typed; a small × button reverts to the dropdown. Custom reasons appear as their own bars on the chart (with a subtle "(custom)" label) and as a "Custom reasons" optgroup in the filter dropdown.
10. **Inline-editable Notes column.** Notes cell is a text input that saves to the row on blur (Enter blurs). No need to enter Edit mode for note updates.
11. **Trimmed NR table layout.** Email and Advisor columns removed from the NR view (the data is still stored on the row from CSV lookup, just not displayed; the add form drops these inputs too). "Registered for Courses" tag moved out of the Name cell into its own column labeled simply "Registered" with a small chip. Final NR columns: ID · Name · Registered · Major · Reason · Notes · Withdrawal · Date Added · Actions.

For the hosted version (Phase 1+), `not_returning_reports.reason` stays as `text` (not `text[]`). The schema in Appendix A is correct.

## Appendix C — What I deliberately left out

- Email/SMS notifications when someone is flagged as not returning
- Bulk export (CSV/Excel) of filtered student lists
- Comments/threading on individual students
- Mobile-optimized layout beyond what the current page does
- Trend charts across CSV snapshots (term-over-term retention rate)

These are all reasonable adds for a Phase 4. Flagging them so they don't get forgotten, not because they're in scope yet.
