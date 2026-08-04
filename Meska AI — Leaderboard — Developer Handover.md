# Meska AI — Final Project Leaderboard
## Developer Handover

**Project:** Claude Course for Professionals — Cohort Awards leaderboard
**Target domain:** `leaderboard.meska.ai`
**Status:** Working front-end prototype. Backend not built.
**Owner:** Meska AI — Learning & Delivery
**Last updated:** 30 July 2026

---

## 1. What this is

A public-vote leaderboard for the cohort's final projects. Participants submit a project with a demo video; the cohort and the public vote across four award categories; an admin reveals the winners at a closing ceremony.

The core design principle, set in the original plan and confirmed by the CEO: **every project is presented with one identical set of fields.** There are no per-category criteria. Voters read the same card for each project and decide for themselves which project deserves each award. This keeps the vote fair — no project can be dressed up differently to chase a category.

---

## 2. What you are receiving

| File | What it is |
|---|---|
| `Meska AI — Leaderboard — Option B (Backend Demo).html` | **The reference implementation.** Full UX for the account-based version, running on a mock in-browser store. This is the spec — build this against a real backend. |
| `Meska AI — Leaderboard — Option A (Links Only).html` | Simpler fallback: no accounts, admin enters everything, demo videos are pasted links. Useful as a contingency if the backend slips. |
| `meska-leaderboard-schema.sql` | A first-pass Postgres/Supabase schema with row-level security. Reviewed but never run against a live project. |
| This document | Spec, data model, and build checklist. |

Both HTML files are **single self-contained files** — no build step, no dependencies, logo embedded as base64. Open directly in a browser. All state lives in `localStorage`.

> **Important:** these prototypes are throwaway. Do not try to grow Option B into production by bolting a backend onto its `Store` module. Use it as the functional and visual specification, and build properly.

---

## 3. Decisions already made

These came out of the CEO review on 29 July 2026 and are **settled** — do not re-litigate them without checking with Learning & Delivery.

1. **Participants upload their own projects.** Not the admin. Rationale: each person owns their submission, so nobody can later claim "I didn't write that." Submissions pass through admin filtration before publishing.
2. **Per-project vote counts are hidden from voters.** Voters see the *total* number of votes cast and a *per-award* total, but never how any individual project is doing. Prevents bandwagon voting.
3. **The leaderboard page is locked** until an admin explicitly reveals it.
4. **No winners are shown anywhere** until that reveal.
5. **Demo videos must appear as real thumbnails,** not bare links, and must play **in-page** — not in a new tab.
6. **Cohort Choice is restricted.** Only people on an admin-managed list may vote in that category. Everyone else votes the other three.
7. **That same list controls who may submit a project.**
8. **Re-submission resets.** If an approved participant submits again, their project goes back to pending review and the votes it had are cleared.
9. **Registration captures leads:** name, email, mobile, job title, company, LinkedIn.

### Open decisions (need an answer before launch)

- **Can one voter give the same project more than one award?** Currently yes. Confirm.
- **Can participants vote for their own project?** There is a `selfVotingAllowed` setting but **it is not enforced anywhere** — it is a reminder flag only. Decide the rule and either enforce it or remove the setting.
- **Project ordering leaks ranking.** The homepage sorts by vote count, so the leading project sits top-left even though numbers are hidden. This contradicts the original plan's anti-bias randomisation. Either accept it, or switch to a per-voter random order (one line — see §6.1).

---

## 4. Roles and permissions

| | Public (registered) | Cohort member | Admin |
|---|---|---|---|
| Browse projects, watch demos | ✅ | ✅ | ✅ |
| Vote Best ROI / Technical / Creative | ✅ | ✅ | ✅ |
| Vote **Cohort Choice** | ❌ | ✅ | ✅ if on the list |
| **Submit** a project | ❌ | ✅ | ✅ if on the list |
| See the leaderboard before reveal | ❌ | ❌ | ✅ (private preview) |
| Approve / reject submissions | ❌ | ❌ | ✅ |
| Manage cohort list, settings, reports | ❌ | ❌ | ✅ |

**Cohort membership = an email on the admin-managed list.** One list, two powers: submit rights and Cohort Choice voting rights. Anyone can register and vote the other three awards.

**Admin** is a flag on the user account. In the prototype it is `isAdmin: true`; in the schema it is `profiles.is_admin`. There is no self-service path to becoming an admin — set it manually in the database. Bootstrap: register normally, then flip the flag.

---

## 5. Pages

| Route | Who sees it | Purpose |
|---|---|---|
| **Vote** (home) | Everyone | Project grid, vote totals box, voting |
| **Leaderboard** | Everyone (locked until reveal) | Rankings, winners celebration |
| **About** | Everyone | How the awards work, the 9 card fields, voting rules |
| **Submit** | Cohort members only | Instructions + submission form |
| **Admin** | Admins only | Review queue, leads, reports, settings, cohort list |

The prototype uses hash routing (`#vote`, `#board`, `#about`, `#submit`, `#admin`) with all views in one document. In production these should be real routes.

### 5.1 Vote page

- **Vote totals box** (always visible): overall total, plus a count per award. **Never per project.**
- **Project grid**: cards with a 16:9 video thumbnail, project name, tagline, participant. Clicking a card opens the project detail view.
- **Project detail**: all nine fields, large video thumbnail, and the four vote buttons.
- Vote buttons show `Vote` or `Your vote` — **no counts**.
- A "viewed everything" gate: by default voters must open every project before their first vote is accepted (`requireViewAll`).

### 5.2 Leaderboard

Locked by default. Shows a padlock and an explanation — **no vote data at all**.

Once `resultsRevealed` is true:
1. Countdown overlay: **3 → 2 → 1 → "🎉 Congratulations!"** (900ms per beat)
2. Fireworks canvas animation starts on the congratulations beat
3. Winners appear: four cards side by side, each with participant **photo**, trophy, **project name**, **participant name**, and vote count
4. Full ranked columns below, with per-project counts
5. A "Replay the reveal" button re-runs the sequence

Admins see the board **before** reveal with an "Admin preview" banner, so numbers can be sanity-checked privately.

Fireworks are skipped entirely under `prefers-reduced-motion`, and stop when the user leaves the tab.

### 5.3 Submit page

Two halves: a "what we need from you" brief (six numbered points covering the video, photo, problem/solution, ROI, tech stack, creative twist), then the form.

Form fields map 1:1 to the project record. Includes a **video file picker** with progress, a **fallback link field**, and a **photo picker**.

If the participant already has a submission, the form pre-fills it and shows current status. Re-submitting an approved project triggers a confirmation warning that votes will be cleared.

### 5.4 Admin

Panels in order:
1. **Submissions awaiting review** — video thumbnail, details, Approve / Reject (with reason) / Edit
2. **Registered voters** — the lead list, CSV export
3. **Report: votes per day** — date, total, and a column per award, CSV export
4. **Report: who voted for what** — name, email, mobile, and the project picked in each award, CSV export
5. **Voting settings** — voting open, require-view-all, self-voting flag, **reveal results publicly**, rules note
6. **Cohort members** — the email list
7. **Projects & approvals** — full CRUD, status toggle

---

## 6. The Standard Project Card

Nine fields, identical for every project. This is the heart of the product — do not add per-category fields.

| # | Field | Key | Notes |
|---|---|---|---|
| 1 | Project name + tagline | `name`, `tagline` | One line, plain language |
| 2 | Participant | `participant`, `photo` | One individual, not a team. Photo shown if they win. |
| 3 | Problem statement | `problem` | 2–3 sentences |
| 4 | Solution overview | `solution` | 2–3 sentences |
| 5 | Demo | `demoLink`, `videoFileName`, `demoShots` | 30–60s video. Anchors the whole thing — people vote with their eyes first. |
| 6 | Impact / ROI note | `impact` | A number, even an estimate. Anchors Best ROI. |
| 7 | Tech stack & hard problem | `techStack[]`, `hardProblem` | Anchors Best Technical |
| 8 | The creative twist | `creativeTwist` | Anchors Best Creative |
| 9 | Live link / repo | `liveLink` | Optional |

Plus system fields: `id`, `status`, `submittedBy`, `rejectReason`, `sample`.

### 6.1 Ordering

```js
// Highest-voted first, ties broken by a per-voter shuffle.
// To restore the original anti-bias behaviour, drop the sort and
// return the shuffle alone.
function orderProjects(projects) {
  const shuffled = Store.seededShuffle(projects, Store.getVoterId());
  const totalFor = p => CATEGORIES.reduce((n, c) => n + (tally(c.id)[p.id] || 0), 0);
  return shuffled
    .map((p, i) => ({ p, i, n: totalFor(p) }))
    .sort((a, b) => (b.n - a.n) || (a.i - b.i))
    .map(x => x.p);
}
```

---

## 7. Data model

### 7.1 Award categories

Fixed, four, hard-coded:

```js
[
  { id: 'roi',       label: 'Best ROI' },
  { id: 'technical', label: 'Best Technical' },
  { id: 'creative',  label: 'Best Creative' },
  { id: 'cohort',    label: 'Cohort Choice' },   // restricted
]
```

### 7.2 Project

```ts
{
  id: string
  name: string
  tagline: string
  participant: string          // display name of the submitter
  photo: string                // data URL in prototype → storage URL in production
  problem: string
  solution: string
  demoType: 'video' | 'screenshots'
  demoLink: string             // YouTube / Drive / Loom / Vimeo
  videoFileName: string        // original filename of an uploaded video
  demoShots: string[]          // optional screenshot labels
  impact: string
  techStack: string[]
  hardProblem: string
  creativeTwist: string
  liveLink: string
  status: 'pending' | 'approved' | 'rejected'
  rejectReason: string
  submittedBy: string          // owner email — one live project per person
  sample: boolean              // demo seed data only; drop in production
}
```

### 7.3 User / lead

```ts
{
  email: string                // primary key, lowercased
  name: string
  title: string
  company: string
  mobile: string
  linkedin: string
  isAdmin: boolean
  createdAt: ISO8601
  // password is plaintext in the prototype ONLY — see §9
}
```

### 7.4 Vote

Prototype shape — one vote per person per category, keyed by identity:

```js
votes    = { [categoryId]: { [voterEmail]: projectId } }
voteMeta = { [categoryId]: { [voterEmail]: ISO8601 } }   // cast timestamp
```

In production this should simply be a `votes` table with a `UNIQUE (category, voter_id)` constraint and a `created_at`. The uniqueness constraint **is** the "one vote per person per category" rule — enforce it in the database, not the UI.

### 7.5 Settings (single row)

```ts
{
  votingOpen: boolean          // master switch
  requireViewAll: boolean      // must open every project before voting
  selfVotingAllowed: boolean   // NOT ENFORCED — see open decisions
  resultsRevealed: boolean     // unlocks the leaderboard for everyone
  rulesNote: string            // free text shown on the vote page
  eventName: string
}
```

### 7.6 Cohort list

A list of lowercased emails. Grants submit rights **and** Cohort Choice voting rights.

---

## 8. Prototype architecture (for reading the reference)

Single HTML file, roughly:

```
<style>          design tokens + all component CSS
<body>
  .demo-banner   (Option B only)
  header.topnav  logo, view tabs, auth area
  section.view#view-vote
  section.view#view-board      + fireworks canvas + countdown overlay
  section.view#view-about
  section.view#view-submit     (Option B only)
  section.view#view-admin
  modals: auth, video player, project editor
<script>
  Store          all state + persistence + rules
  render helpers renderVideoThumb / renderTile / renderCard / renderVotePills
  VideoPlayer    in-page embed player
  view switcher  setView / onViewChange
  Auth           register / login / gating          (Option B only)
  Submit module  photo + video pickers              (Option B only)
  Vote module    grid, detail, voting
  Leaderboard    lock, winners, fireworks, reveal
  Admin          queue, leads, reports, settings, CRUD
```

Everything reads and writes through `Store`, and every module re-renders via `Store.subscribe(fn)`. That seam is why the prototype could be repointed at a real API — but again, treat it as spec, not a starting codebase.

`localStorage` keys are namespaced per file (`meskaA_lb_*`, `meskaB_demo_*`) so the two prototypes never collide.

---

## 9. What must change for production

### 9.1 Authentication — highest priority

The prototype stores **passwords in plain text in `localStorage`**. This is deliberate and clearly commented, because it is a throwaway demo with no server. It must never ship.

Use a real auth provider (Supabase Auth, Auth0, Clerk — the schema assumes Supabase). Requirements:
- Email + password registration capturing the lead fields
- Session persistence
- `is_admin` flag on the profile, settable only in the database
- Decide on email confirmation. For a live event, confirmation-on is safer for lead quality but slower on the day; confirmation-off gets people voting instantly. Ops preference so far has been **off** for speed.

### 9.2 File storage

Two uploads, neither of which really exists yet:

- **Demo video** — up to ~200 MB. In the prototype the file never leaves the browser; it is held as an in-memory object URL that dies on reload. Needs real object storage with resumable upload, a size/type limit, and ideally transcoding or at least a poster frame.
- **Participant photo** — the prototype downscales to a 220×220 JPEG data URL (~3 KB) via canvas, which is a reasonable trick to keep but should still end up in object storage.

Also handle: what happens to the old video when someone re-submits.

### 9.3 Realtime

The leaderboard should update live during the ceremony without refreshes. The prototype fakes this with a 4-second poll plus same-browser `storage` events. Use proper realtime subscriptions (Supabase Realtime, WebSocket, or SSE) on the votes and projects tables.

### 9.4 Server-side rule enforcement

Everything below is currently enforced in the browser only and **must** move server-side:

| Rule | Enforcement |
|---|---|
| One vote per person per category | `UNIQUE (category, voter_id)` |
| Cohort Choice restricted | Trigger checking the voter's email against the cohort list — see the schema's `check_cohort_eligibility()` |
| Only cohort members may submit | Row-level security on insert |
| Only admins approve/reject/configure | RLS via an `is_admin()` helper |
| Voting closed | Reject writes when `voting_open` is false |
| Results hidden before reveal | **Do not send vote counts to non-admin clients at all** while `results_revealed` is false. Hiding them in the UI is not enough — anyone can open devtools. |

That last one matters. In the prototype the counts are present in the client and merely not rendered. In production, the API must not return them.

### 9.5 Re-submission behaviour

Implement as a transaction: replace the project record, set status back to `pending`, clear `reject_reason`, and **delete every vote pointing at that project**. Reference implementation is `Store.submitProject()`.

---

## 10. Build checklist

**Foundations**
- [ ] Auth with lead capture (name, email, mobile, title, company, LinkedIn)
- [ ] Profiles table with `is_admin`
- [ ] Cohort email list, admin-managed
- [ ] Settings singleton
- [ ] Object storage for video + photo

**Participant**
- [ ] Submit page: instructions + form, gated to cohort members
- [ ] Video upload with real progress; link fallback
- [ ] Photo upload
- [ ] Status view: pending / live / sent back with feedback
- [ ] Re-submission clears votes and returns to pending

**Voter**
- [ ] Project grid with real video thumbnails
- [ ] Project detail with all nine fields
- [ ] In-page video player (YouTube / Vimeo / Drive embeds + uploaded files)
- [ ] Four vote buttons, no counts, toggleable
- [ ] Cohort Choice blocked for non-members, with a clear message
- [ ] Vote totals box: overall + per award only
- [ ] View-all gate

**Admin**
- [ ] Review queue with Approve / Reject + reason / Edit
- [ ] Leads table + CSV
- [ ] Votes-per-day report + CSV
- [ ] Who-voted-for-what report + CSV
- [ ] Settings incl. reveal toggle
- [ ] Private board preview before reveal

**Ceremony**
- [ ] Leaderboard locked until reveal
- [ ] 3-2-1 countdown → congratulations → winners
- [ ] Winners: photo + project name + participant, side by side
- [ ] Fireworks background, reduced-motion safe
- [ ] Replay control
- [ ] Verify on the actual projector and resolution before the event

---

## 11. Deployment

- **Domain:** `leaderboard.meska.ai`
- Static front end (Netlify / Vercel / Cloudflare Pages) + managed backend is sufficient; there is no heavy server-side compute.
- Add the production origin to the auth provider's allowed redirect URLs.
- **Load:** trivial. One cohort, tens of concurrent voters. Do not over-engineer. The only spike is everyone opening the leaderboard at reveal time.
- Have a fallback: if the backend fails on the day, Option A runs from a single file with no network at all.

---

## 12. Brand

| Token | Value |
|---|---|
| Meska Blue | `#2563EB` |
| Deep Navy | `#0B1E3A` |
| Royal Blue | `#1D4ED8` |
| Light Blue | `#93C5FD` |
| Ice Blue | `#EFF6FF` / `#DBEAFE` |
| Gold (winners) | `#FBBF24` / `#FDE68A` |
| Body text | `#1F2937` |
| Muted | `#6B7280` / `#9CA3AF` |
| Signature gradient | `linear-gradient(150deg, #0B1E3A 0%, #14315E 45%, #1D4ED8 130%)` |

**Font:** Poppins — 700 titles, 500 emphasis, 300 body.
**Logo:** use the supplied transparent PNGs; never recreate or recolour. White wordmark on dark, dark wordmark on light.

Design details worth preserving: gradient section bands with a faint grid overlay and radial glow, rounded cards with soft shadows, pill-shaped tags, uppercase letter-spaced kickers.

---

## 13. Known limitations of the prototypes

1. **No backend.** Everything is `localStorage`; nothing syncs across devices.
2. **Plaintext passwords** in Option B's mock store. Demo only.
3. **Uploads are simulated.** The video never leaves the browser and does not survive a reload.
4. **Vote counts are present client-side** even when hidden — fix in the API layer.
5. **`selfVotingAllowed` does nothing.**
6. **Ordering leaks relative ranking** (see §3).
7. **Option A cannot produce the per-voter report** — it has no identities.
8. Sample/seed projects are marked `sample: true`; strip them.

---

## 14. Contacts

- **Product / requirements:** Meska AI — Learning & Delivery
- **Source material:** CEO review recording, 29 July 2026, and the original *Final Project Leaderboard Plan* PDF

*© 2026 Meska AI — Confidential*
