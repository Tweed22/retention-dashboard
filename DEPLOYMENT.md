# Retention Dashboard — Deployment Walkthrough

**Audience:** Tony (admin)
**Purpose:** the account-level setup steps that have to happen *before* Phase 1 code can be written and deployed. Read this top to bottom; everything in here is something only you can do (account creation, environment variables, payment defaults).

---

## What you're standing up

| Component | Purpose | Cost at our scale |
|---|---|---|
| **Supabase** | Postgres database, magic-link auth, REST API, real-time subscription | Free tier covers us comfortably |
| **Cloudflare Pages** | Hosts the static HTML dashboard, fast global delivery | Free tier covers us comfortably |
| **GitHub** (or GitLab) | Source repo Cloudflare Pages deploys from | Free for private repos |

Everything stays free unless we cross thresholds we won't hit (>500MB Postgres, >100k auth users). I'll add billing alerts to both accounts as a backstop.

---

## Step 1 — Create a GitHub repo

If you already have one for this project, skip ahead. Otherwise:

1. Go to https://github.com/new while signed in.
2. Repo name: `retention-dashboard` (or whatever you like).
3. **Visibility: Private.** Don't make this public — even though there's no PII in the source code, a private repo is the right default for institutional tooling.
4. Initialize with a README (we'll overwrite it).
5. Click "Create repository."

Once created, send me the repo URL — I'll push the current dashboard + the new auth-aware code to it once your other accounts are set up.

If you'd rather use GitLab or Bitbucket, both work with Cloudflare Pages. Tell me which and I'll adjust.

---

## Step 2 — Create a Supabase project

1. Go to https://supabase.com → Sign in (use a college email if available — easier for IT to vouch for later).
2. After signing in, click **New project**.
3. Organization: create one named after your institution, or use the default.
4. **Project name:** `retention-dashboard`.
5. **Database password:** click "Generate a password" and **save it somewhere safe** (e.g. your password manager). You won't need it day-to-day, but you'll want it if we ever need direct SQL access.
6. **Region:** pick the one closest to you geographically. For most of the US this is `East US (North Virginia)` or `West US (Oregon)`.
7. **Pricing plan:** Free.
8. Click **Create new project.** Provisioning takes ~2 minutes.

Once it's up, send me three values from **Project Settings → API**:

- **Project URL** (looks like `https://abcdefghij.supabase.co`)
- **Project ref** (the subdomain part, e.g. `abcdefghij`)
- **anon public key** (a long JWT string)

These are safe to paste in chat — `anon` is meant to be public; the row-level security policies are what actually protect the data. The `service_role` key is the secret one — never share that.

---

## Step 3 — Configure Supabase Auth

In your new Supabase project:

1. Go to **Authentication → Providers.**
2. **Email** should already be enabled. Open it.
3. Toggle **Enable email confirmations: ON.**
4. Toggle **Enable email change confirmations: ON.**
5. Under **Email magic link**, make sure it's enabled. (We don't need passwords — magic-link only.)
6. **Site URL:** leave blank for now; we'll fill this in after Cloudflare Pages gives us a URL in step 4.
7. Save.

Then go to **Authentication → URL Configuration**:

- **Redirect URLs:** add `http://localhost:3000` for local testing. We'll add the production URL after step 4.

We'll add your email and any committee members' emails to the `committee_members` allowlist table once I've run the migration in step 5.

---

## Step 4 — Create a Cloudflare Pages project

1. Go to https://dash.cloudflare.com → Sign up (or sign in).
2. In the sidebar, click **Workers & Pages.**
3. Click **Create application → Pages → Connect to Git.**
4. Authorize Cloudflare to access your GitHub account, then pick the `retention-dashboard` repo.
5. **Project name:** `retention-dashboard` (or your preference — this becomes the URL: `<name>.pages.dev`).
6. **Production branch:** `main`.
7. **Build settings:**
   - Framework preset: **None**
   - Build command: leave blank
   - Build output directory: `/` (the repo root)
8. **Environment variables** (click "Add variable" for each):
   - `SUPABASE_URL` = the Project URL from step 2
   - `SUPABASE_ANON_KEY` = the anon public key from step 2
9. Click **Save and Deploy.**

The first deploy will be just the existing HTML (no auth yet) — that's expected; it gives us a URL to feed back into Supabase.

After deploy completes, copy your production URL (e.g. `https://retention-dashboard.pages.dev`) and:

- Go back to Supabase → **Authentication → URL Configuration**
- Set **Site URL** to the Cloudflare URL
- Add the same URL to **Redirect URLs**
- Save

This closes the loop so magic-link emails redirect users back to your hosted dashboard.

---

## Step 5 — Run the database migration (I'll do this with you)

Once steps 1–4 are done, I'll write `supabase/migrations/0001_init.sql` containing all the tables (`students`, `csv_snapshots`, `snapshot_metrics`, `terms`, `withdrawals`, `not_returning_reports`, `committee_members`, etc.) plus the RLS policies from section 4 of the architecture plan.

You apply it by:

1. Going to **SQL Editor** in Supabase.
2. Pasting the migration SQL.
3. Clicking **Run.**

Or via the Supabase CLI if you'd rather (`supabase db push`). I'll provide both.

After migration, you'll seed the `committee_members` table with a row for yourself (`role='admin'`) and rows for each committee member (`role='member'`). I'll provide the SQL.

---

## Step 6 — Test the magic-link flow

Once auth is wired up:

1. Visit your dashboard URL.
2. Click "Sign in" in the header.
3. Enter your email.
4. Check your inbox — Supabase sends a one-time link.
5. Click the link → you should land back on the dashboard, signed in, with all detail tabs visible.

If the email doesn't arrive: check spam first; then check **Authentication → Email templates** in Supabase to see if there's a delivery error.

---

## Step 7 — Routine operation

Day-to-day after launch:

- **Uploading new CSVs:** sign in, go to `/admin`, drag the four CSVs in, click Apply. Real-time subscription pushes the update to any open viewer within ~1 second.
- **Adding a new committee member:** sign in as admin, open Settings → Committee Members → Add → enter email + display name. They can sign in immediately — no manual approval needed.
- **Removing a committee member:** Settings → Committee Members → toggle "Active" off. Their existing submissions stay visible; future logins are rejected.

---

## What I need from you to start writing Phase 1 code

1. ✅ GitHub repo URL (step 1)
2. ✅ Supabase Project URL + ref + anon key (step 2)
3. ✅ Cloudflare Pages project name + production URL (step 4)
4. ✅ Confirmation that institutional clearance for Supabase + Cloudflare is still in place — the public-facing Summary expands the surface area slightly vs. the original committee-only plan, so worth a quick sanity check with whoever cleared this before.

Once I have these four, I'll write the migration SQL, the auth-aware client code, and the admin upload page — landing as a single PR you can review before merging.

---

## Cost & quota guardrails

I'll set both of these up the same day we deploy:

- **Supabase:** project settings → set a billing alert at 80% of free-tier limits (database size, bandwidth, monthly active users). At our scale we won't hit any of these, but the alert is cheap insurance.
- **Cloudflare:** Pages free tier is generous (500 builds/month, unlimited requests). No billing setup needed — we won't exit the free tier.

If we ever do exit free tier, the next paid step is ~$25/month for Supabase Pro. We're nowhere near that.

---

## Open questions / things to flag with IT

Worth a 10-minute check before going live:

- **Is the institution OK with student-PII data sitting in Supabase's US-East region?** Supabase signs DPAs/BAAs but the region matters for some compliance regimes.
- **Does email-magic-link satisfy the auth posture IT prefers, or do they want SSO?** Magic-link is simpler; SSO is the gold standard. The schema supports either.
- **Is `pages.dev` an acceptable hostname or do you want a custom subdomain?** (e.g. `retention.yourcollege.edu` — that's a CNAME away once you decide.)
