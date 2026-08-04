---
name: meska-project-page
description: Turns a participant's live application URL into a branded Meska project page for the Final Project Leaderboard — explores the app, captures a screenshot, writes the nine standard card fields, and emits a self-contained HTML file the admin uploads. Use whenever someone gives a link to a cohort member's final project and asks for the project page, the leaderboard HTML, "create the html for this project", or wants the metadata filled in from an app. Also use when re-generating or updating an existing project page.
---

# Meska — Final Project Page Generator

Produces the HTML page that represents one participant's project on the Meska AI Final Project Leaderboard. The admin uploads the output in **Admin → Projects → Add project**, where the embedded metadata block auto-fills every field.

## The one rule that matters

**Explore the app before writing a single word about it.** The whole point is a page that describes what the project actually does. Writing from the URL, the app's name, or a guess produces a card that misrepresents someone's work in front of their cohort and a CEO.

Equally: **never invent what you cannot observe.** Three fields are routinely unknowable from the outside — the participant's name, a business ROI figure, and which Claude features were used. Mark those `to confirm` rather than filling them with something plausible. A page with three honest gaps is far better than one with three confident inventions.

## Steps

### 1. Check whether it can be embedded

```bash
curl -sSI <URL> | grep -iE "x-frame-options|content-security-policy|^HTTP"
```

No `X-Frame-Options` and no CSP `frame-ancestors` means the live app can sit in an iframe on the page — voters can use the real thing. If either header blocks framing, drop the live embed and keep the screenshot plus an "Open the app ↗" button. Do not ship a silently-broken empty frame.

### 2. Explore the app properly

Open it in the browser and actually move through it. Read the real screens, not just the landing page:

- What does it do, for whom, and what breaks without it?
- Walk the primary flow end to end. Note the mechanism — steps, scoring, rules, states.
- Find the screen that carries the product's argument (often a "how it works", results, or settings view). That is usually where the creative twist lives.
- Note exact in-product wording, especially non-English. Quoting the product's own language makes the page ring true.
- Look for a demo-data disclaimer and repeat it on the page if present.

`get_page_text` on each key route is usually faster and cheaper than screenshots for understanding. Use screenshots to judge design.

### 3. Capture the tile screenshot

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --window-size=1280,800 --virtual-time-budget=12000 \
  --screenshot="shot.png" "<URL>"
```

Then crop dead space and compress — the file gets embedded as a data URI, so size matters:

```python
from PIL import Image; import base64, io
im = Image.open("shot.png").convert("RGB")
im = im.crop((0, 0, 1280, 700))          # trim empty footer + any builder badge
im = im.resize((1000, 547), Image.LANCZOS)
buf = io.BytesIO(); im.save(buf, "JPEG", quality=80, optimize=True)
print(len(buf.getvalue()) // 1024, "KB")  # aim under ~60 KB
b64 = base64.b64encode(buf.getvalue()).decode()
```

Pick a frame that shows the product working, not a splash or a cookie banner.

### 4. Write the nine fields

| Field | How to fill it |
|---|---|
| Project name | The product's own name. Keep native script alongside a transliteration if not Latin. |
| Tagline | Prefer the product's own line if it has a good one. |
| Participant | **Never invent.** Mark `to confirm` unless supplied. |
| Problem | 2–3 sentences: what breaks today and for whom. Concrete, not abstract. |
| Solution | 2–3 sentences: what they actually built, in plain language. |
| Impact / ROI | Use an **observed** number if the app shows one (counts, timings, reductions). Say it was observed. Flag that a business figure should come from the participant. |
| Tech stack | Only what you can verify — the builder platform, visible framework. Mark Claude usage `to confirm`. |
| Hard problem | The genuinely difficult thing, judged from the product's behaviour. Anchors Best Technical. |
| Creative twist | The unexpected decision. Anchors Best Creative. |

Write for a reader who has 30 seconds. Specific beats effusive: name the mechanism, quote the product, avoid "revolutionary", "seamless", "powerful".

### 5. Build the page from the template

`assets/template.html` is the validated Khatba-derived layout: Meska gradient hero, live-embed card, field grid, mechanism panels, quote block, `to confirm` chips. Replace the content, keep the structure and CSS.

Adapt where the project differs — the two "mechanism" boxes were pillars/blockers for a matching engine; use whatever the actual mechanism is, or drop the section if there isn't one worth showing.

### 6. Emit the metadata block — required

The admin panel reads this to auto-fill. Without it the admin retypes everything. Place it immediately before `</head>`:

```html
<script type="application/json" id="meska-project-meta">
{
  "name": "…",
  "tagline": "…",
  "participant": "…",
  "problem": "…",
  "solution": "…",
  "impact": "…",
  "techStack": ["…", "…"],
  "hardProblem": "…",
  "creativeTwist": "…",
  "liveLink": "example.com",
  "projectUrl": "https://example.com/"
}
</script>
```

Keys must match exactly — they map onto the admin form. `techStack` is an array. Optional `photo` takes a data URI and fills the participant photo too. Values must match the visible page; the block is the same content, not a second version of it.

### 7. Verify before handing over

Serve it locally and load it. Confirm:

- No console errors, layout holds at desktop and ~700px
- The live embed actually renders (or is correctly absent if framing is blocked)
- `document.getElementById('meska-project-meta')` parses as JSON
- RTL text sits correctly — `direction: rtl` on a block element pushes it to the right edge; use `display: inline-block` to keep it with left-aligned content

Deliver as `project-<name>.html` and tell the admin which fields are marked `to confirm`.

## Traps worth knowing

**Escaping.** When HTML is placed inside an attribute (`srcdoc`), quotes must be escaped or the content truncates at the first `"`. The leaderboard handles this, but never hand-build such an attribute with a naive escape.

**Live embeds are a dependency.** Embedding the participant's hosted URL means the card changes if they unpublish or edit it. Say so when delivering. The screenshot and metadata survive regardless.

**Builder badges.** Lovable/Framer/Bubble badges sit bottom-right. The 700px crop removes them.

**Non-Latin type.** Load a suitable webfont (e.g. IBM Plex Sans Arabic) and set `direction: rtl` on those blocks only, with `unicode-bidi: isolate` where mixed with English.

## Brand

Navy `#0B1E3A` · Meska Blue `#2563EB` · Royal `#1D4ED8` · Light Blue `#93C5FD` · Ice `#EFF6FF` · Gold (winners only) `#FBBF24` · Body `#1F2937` · Muted `#6B7280`

Gradient: `linear-gradient(150deg,#0B1E3A 0%,#14315E 45%,#1D4ED8 130%)` · Font: Poppins (700/500/300)

See the bundled `meska-branding` skill for logo files if a logo is needed.
