# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The Final Project Leaderboard for Meska AI's "Claude Course for Professionals" cohort — participants
submit projects, the cohort and public vote across four fixed awards, and an admin reveals winners at a
closing ceremony. Target domain `leaderboard.meska.ai`.

There is **no build system, no package manager, no test suite, and no git repository**. Every deliverable
is a single self-contained HTML file: all CSS, all JS, and the logo (base64) inline. The only external
dependencies are the Google Fonts stylesheet and the Supabase JS CDN bundle.

## Files

| File | Role |
|---|---|
| `meska-leaderboard-live.html` | **The real build.** Supabase-backed. The only file to change for product work. |
| `meska-leaderboard-schema-v2.sql` | Live schema — tables, RLS, triggers, safe-aggregate RPCs. Already applied. Idempotent. |
| `project-khatba.html` | Example participant project page with its `meska-project-meta` block. |
| `meska-project-page/` | Skill that generates those project pages from a live app URL. |
| `Meska AI — Leaderboard — Option A (Links Only).html` | Zero-backend contingency for ceremony night. |
| `Meska AI — Leaderboard — Option B (Backend Demo).html` | localStorage prototype — the UX spec the live build was made from. |
| `Meska AI — Leaderboard — Developer Handover.md` | Requirements and settled decisions. **Sections 8–13 are stale** — written before the Supabase build. |

Superseded, keep but never run: `Meska AI — Final Project Leaderboard.html`, `meska-leaderboard-schema.sql`,
`meska-schema-fix-grants.sql`.

Filenames contain em dashes and spaces — quote paths in shell commands.

## Running and verifying

Supabase auth needs an http origin, so serve rather than opening from `file://`:

```bash
python3 -m http.server 8000
```

Then load `http://localhost:8000/meska-leaderboard-live.html`. Verification is manual: check the browser
console, walk the affected view, and confirm at desktop width and ~700px. `Store.lastError()` surfaces the
last Supabase failure, and `Store` is a live handle in the console — `Store.getApprovedProjects()`,
`Store.tally('roi')`, `Store.getSettings()` answer most questions faster than reading the DOM.

Two environment traps, both verified on this machine:

- **The project lives in `~/Downloads`, which macOS TCC blocks for spawned helper processes.** A server
  started from a normal Bash shell works; one started by a preview/launch helper dies with
  `getcwd: Operation not permitted` before it parses its arguments. `--directory` does not help — the
  failure happens at argparse default construction. Start the server from Bash, or move the project out
  of `~/Downloads`.
- **Headless Chrome is the reliable way to see a rendered view.** Screenshots of a backgrounded browser
  pane can return stale blank frames that look like a broken layout while the DOM is provably fine.
  Confirm against geometry (`getBoundingClientRect`, computed `opacity`) before believing a blank shot.

To screenshot a state that needs interaction, copy the file to a scratch dir and append a small harness
before `</body>` that awaits `Store.ready`, clicks its way in, then screenshot with
`--virtual-time-budget`. Give the window enough height to capture the page without scrolling — scrolling
a headless capture tears sticky elements.

**This build points at the live production Supabase.** There is no local or seed database. Anything you
click writes to the real event: casting a vote, approving a project, or flipping *Reveal results* is a
production change. Drive it read-only unless the user has asked for a write.

Schema changes go through Supabase → SQL Editor. `meska-leaderboard-schema-v2.sql` is written to be
re-runnable (`create ... if not exists`, `drop policy if exists`), so edit it and re-run the whole file
rather than writing one-off patches — that is what `meska-schema-fix-grants.sql` was, and it is now dead.

## Architecture of the live build

One document, ~3500 lines, in three parts: a `<style>` block with design tokens plus all component CSS,
five `<section class="view">` elements, and one `<script>`. Major regions are separated by
`/* ==== NAME ==== */` banner comments — grep those to navigate.

```
Store            Supabase client, in-memory cache, all reads/writes/rules
render helpers   escapeHtml / escapeAttr / safeUrl / videoMeta / renderTile / renderCard
view switcher    #vote #board #about #submit #admin — hash routing, all views in one document
Auth             register / login / gating
VOTE module      grid, project detail, vote pills
LEADERBOARD      lock state, rankings, countdown, fireworks canvas
ADMIN            review queue, leads, reports, settings, roster, project CRUD
```

**The `Store` seam is the whole design.** The UI reads synchronously from an in-memory cache
(`_projects`, `_settings`, `_myVotes`, `_totals`, `_standings`) and re-renders through
`Store.subscribe(fn)`. Writes are async, hit Postgres, refresh the affected slices of cache, then
`notify()`. Every render path is therefore identical to the localStorage prototype it came from. New
features should follow that shape: add a fetcher, add it to `refreshAll()`, expose a synchronous getter,
and let subscribers redraw. Do not have UI modules query Supabase directly.

Realtime subscriptions on `votes`, `projects` and `settings` keep the ceremony live without refreshes.

### Security model — read before touching vote data

Hidden standings are enforced in the **database**, not the UI. `public.standings()` raises
`results_not_revealed` unless an admin calls it or `settings.results_revealed` is true, so
`Store.tally()` is simply empty before the reveal and the board renders its locked state. There is no
client-side secret. `public.vote_totals()` returns per-award totals only — never per project.

Other rules that live in Postgres and must stay there:

- `unique (category, voter_id)` on `votes` **is** "one vote per person per category".
- The `enforce_vote_rules` trigger rejects votes when voting is closed, and rejects `cohort` votes from
  anyone not on the roster.
- RLS: voters read only `status = 'approved'` projects; authors read their own; admins read all.
- `public.roster` is one list with two powers — who may submit, and who may vote Cohort Choice.
  `i_am_cohort()` / `is_on_roster()` let a client check eligibility without reading the list.
- `profiles.is_admin` is set only by hand in SQL. There is no self-service path.

Never move an enforcement point into JavaScript to make something easier. Probed against the live
database with the anon key on 4 Aug 2026: `standings()` raises `results_not_revealed`,
`select * from votes` returns `permission denied for table votes`, `vote_totals()` returns per-award
counts only, and `projects` yields approved rows only. The design holds under direct API attack, not
just through the UI.

Re-submission (`Store.submitProject`) deletes every vote pointing at the project, resets status to
`pending`, and clears `reject_reason`. Preserve that.

The `SUPABASE_ANON_KEY` embedded in the HTML is the **anon** key and is meant to be public — RLS is what
protects the data. The `service_role` key must never appear in a file, a commit, or a chat.

## Project pages

Projects are represented by a participant-specific HTML page stored as text in `projects.project_html`
(~20 KB) plus a small data-URI `screenshot`. No object storage is involved. The page is rendered inside an
`<iframe srcdoc="…">`, which is why `escapeAttr()` escapes quotes — a naive escape truncates the document
at the first `"`.

The project detail view shows an **"Open the full project ↗"** button, not an inline embed; the `srcdoc`
iframe lives in a modal opened by the `[data-open]` delegated click handler. An absent iframe in the
detail view is correct, not a bug.

Each page carries a `<script type="application/json" id="meska-project-meta">` block immediately before
`</head>`. The admin panel parses it and auto-fills the form; the keys map through `META_TO_FIELD` in the
ADMIN module and must match exactly: `name`, `tagline`, `participant`, `problem`, `solution`, `impact`,
`techStack` (array), `hardProblem`, `creativeTwist`, `liveLink`, `projectUrl`, optional `photo` (data URI).
Missing block → the admin retypes everything. `project-khatba.html` is the reference; changes to the field
set must be made in three places — the schema, `META_TO_FIELD`, and `meska-project-page/SKILL.md`.

## Settled product decisions

From the CEO review of 29 July 2026. Do not re-litigate without Learning & Delivery:

- **One identical card for every project** — nine fields, no per-category fields. This is the fairness
  guarantee, and it is the constraint most likely to be broken by a well-meaning addition.
- Participants submit their own projects; admin filters before publishing.
- Per-project counts are hidden from voters — only overall and per-award totals are shown.
- The leaderboard stays locked until an admin explicitly reveals it.
- Cohort Choice, and submission rights, are restricted to the roster.

Still open (documented in the handover §3): whether one voter may give the same project multiple awards;
whether participants may vote for themselves (`self_voting_allowed` exists but **is not enforced anywhere**);
and that the homepage sort by vote count leaks relative ranking despite the counts being hidden
(`orderProjects()` in the VOTE module — dropping the sort restores the anti-bias shuffle).

## Brand

CSS custom properties at the top of each file are the source of truth: `--navy #0B1E3A`,
`--navy-2 #14315E`, `--royal #1D4ED8`, `--blue #2563EB`, `--blue-light #93C5FD`, `--ice #EFF6FF`,
gold for winners only. Signature gradient `linear-gradient(150deg,#0B1E3A 0%,#14315E 45%,#1D4ED8 130%)`.
Poppins — 700 titles, 500 emphasis, 300 body. Logos are the supplied transparent PNGs; never recreate or
recolour them.

Fireworks and the countdown overlay must stay skipped under `prefers-reduced-motion`.
