# Install — "Meska Project Page" skill

Turns a participant's live application URL into a branded Meska project page for
the **Final Project Leaderboard**. It explores the app, captures a screenshot,
writes the nine standard project-card fields, and emits a self-contained HTML
file. The admin uploads that file in **Admin → Projects → Add project**, where an
embedded metadata block fills every field automatically.

## What's in this folder
- `SKILL.md` — the skill (instructions + trigger).
- `assets/template.html` — the validated project-page layout: Meska gradient
  hero, live-embed card, nine-field grid, mechanism panels, and the
  "to confirm" chips.
- `INSTALL.md` — this file.

## Install

**Claude desktop / web — Skills manager (this is the one that works here):**
1. Open **Settings → Skills**.
2. Choose **Add skill / Upload**, and give it this `.zip`
   (or the `meska-project-page/` folder if it asks for a folder).
3. Restart the app so the session picks it up.

**Claude Code CLI:**
1. Copy the whole **`meska-project-page/`** folder into your skills directory:
   - User-level: `~/.claude/skills/meska-project-page/`
   - Project-level: `<your-project>/.claude/skills/meska-project-page/`
2. Start a new session (or run `/clear`).

> Dropping the folder on disk does **not** register it with the desktop app's
> Skills manager — that reads its own store. Upload the zip there instead.

## Use it

Paste a link and ask for the page:

> "Here's the next project: https://something.lovable.app/ — make the project page."

Or invoke it explicitly with **`/meska-project-page`**.

Output is `project-<name>.html`, ready to upload in the leaderboard admin panel.

## What it will not do

Three fields cannot be known from outside an app, and the skill deliberately
marks them **`to confirm`** rather than inventing them:

- the **participant's name**
- a **business ROI figure** (it uses an observed number instead, and says so)
- **which Claude features** were used

Fill those in from the participant, either in the admin panel or by telling
Claude before it generates the page.

## Requirements

- Google Chrome installed (used headlessly for the screenshot).
- Python with Pillow, for cropping and compressing that screenshot.
- Browser access, so the skill can actually explore the app before describing it.
