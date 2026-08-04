# Claude Leaderboard — file index

Final Project Leaderboard for the Claude Course for Professionals cohort.
Target address: **leaderboard.meska.ai**

## Use these

| File | What it is |
|---|---|
| `index.html` | **The real build.** Connected to Supabase. This is what gets deployed — the name makes it the site root. |
| `meska-leaderboard-schema-v2.sql` | Database schema — tables, row-level security, safe aggregates. Already applied. |
| `project-khatba.html` | Khatba project page, with its metadata block. Uploaded through the admin panel. |
| `khatba-screenshot.png` | Thumbnail image for Khatba. |

## Backups / fallbacks

| File | What it is |
|---|---|
| `Meska AI — Leaderboard — Option A (Links Only).html` | No accounts, no database. Opens from the file itself. Ceremony-night contingency. |
| `Meska AI — Leaderboard — Option B (Backend Demo).html` | Full feature demo on browser storage. Useful for showing the flow without a login. |

## Reference

| File | What it is |
|---|---|
| `Meska AI — Final Project Leaderboard Plan.pdf` (+ `(1)`) | The original brief. `(1)` is the later of the two. |
| `hqv-kwan-onh (2026-07-29 14_34 GMT+3).mp4` | CEO review meeting recording. |
| `Meska AI — Final Project Leaderboard — Developer Handover.pdf` / `.md` | Handover doc. **Partly out of date** — written against the browser-storage prototype, before the Supabase build. |
| `meska-leaderboard-leads.csv` | Sample lead export format. |
| `meska-project-page/` + `.zip` | Draft skill for generating project pages from an app URL. Parked. |

## Superseded — keep for history, do not run

- `Meska AI — Final Project Leaderboard.html` — the first single-file version.
- `meska-leaderboard-schema.sql` — v1 schema. Replaced by v2.
- `meska-schema-fix-grants.sql` — a patch already folded into the live database.

## Where the data lives

Supabase project `zxokeevbviqwfuxnnygf`. The key embedded in the live HTML is the
**anon** key, which is meant to be public — row-level security is what protects the
data. The **service_role** key must never go in a file or a chat.

Admins: `learn@meska.ai` and `amrkhattab@meska.ai` — pre-authorised, so they become
admins automatically when they register.
