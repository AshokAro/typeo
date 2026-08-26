# Typeo — Build Ledger

*Status as of 27 August 2026.* Everything the app does today, measured against the
version boundaries in [CLAUDE.md](CLAUDE.md), and an ordered starting point for what
comes next.

| | |
|---|---|
| Commits | 17 |
| Swift | 41 files, ~7,400 lines |
| Self-checks | 83, all passing |
| Shader effects | 18 selectable |
| Versions | 5 of 6 shipped |

---

## The plan, version by version

The value of having written the boundaries down is visible here: five versions in a row
shipped without the model being reshaped once.

### v1 — Type, style, export · **Shipped**

Planned: type → curated font list → one colour and one Core Image filter → three aspect
ratios → export to Photos and the share sheet.

Delivered in full. One deviation that turned out to matter: Core Image was dropped at v2
for real Metal shaders, so the filter shipped in v1 is the only Core Image code that ever
existed.

### v2 — Shader set and a gallery · **Shipped**

Planned: bloom, heat, noise and glitch as Metal shaders on the text block; an in-app
gallery persisting `Composition` as JSON.

Delivered, and overtaken. Four shaders became eighteen; the gallery still stores one JSON
file per composition, exactly as designed.

### v3 — Individually addressable glyphs · **Partly**

Planned: the canvas rebuilt as SpriteKit glyph nodes, per-letter jumbling, and
tap-and-hold inflate / float / gravity.

Delivered, with one thing still unclaimed. Letters diverge through shuffle and physics,
but there is still no way to select a single letter and style it. The model has supported
that since v1 — it is the largest capability in the app that no interface reaches.

### v4 — Video export · **Shipped**

Planned: offscreen frame-by-frame rendering into `AVAssetWriter`, saved to Photos or
shared.

Delivered, and since rebuilt. A fixed four-second take became a 3–2–1 count-in and an open
recording you end yourself, capped at sixty seconds.

### v5 — Widget · **Blocked**

Planned: pin compositions to a shared manifest, rotate them on a timeline, preview at real
widget sizes.

App side complete; the extension cannot be built. A WidgetKit target needs an App Group,
which needs a paid developer account. The source is written and waiting in `TypeoWidget/`,
and `TypeoSharedStore` is the seam — when the account arrives, no code changes, only
entitlements and one re-pin.

### v6 — The overhaul added along the way · **Beyond plan**

Never in the original plan: in-canvas text editing, a paper-shaders-grade effect library
on text and background independently, letter-shaped collision, device tilt, photo
backgrounds, and the interface rebuilt around them.

This is now most of the app. Eleven of the seventeen commits are v6, and it never once
required the model to change shape.

---

## What the app does today

### Canvas — 3 ratios
- Tap anywhere to place a caret and type, on the canvas itself
- 1:1, 9:16 and 16:9, each laid out at a fixed reference size
- Preview and export run the same view at the same logical size
- Undo and redo, with a burst of typing collapsing into one step
- No autocorrect or dictation — the caret is the app's own

### Type — 20 faces
- Four system designs plus up to sixteen device faces, filtered for availability
- Every row previews your actual typed text, never sample text
- Size 40–420, in the same panel as the typeface
- Alignment, letter spacing −30–120, line height 0.6–2.2

### Fill — text and background
- One Text / Background tab governs fill and effect together
- Solid, gradient with an angle, or — for the background — a photo
- Six built-in backgrounds, drawn rather than bundled
- Any photo from the library, stored outside the model by id

### Effects — 18 kinds
- Applied to text and background independently, as separate layers
- Two or three sliders each, named for what they actually do
- Discrete choices where they belong: noise type, dither pattern, mesh shape
- Six one-tap presets that write both layers at once
- Retired effects stay decodable — a saved file never breaks

### Motion — 5 modes
- Warp, Attract, Gravity and Tilt, every one bipolar and inert at zero
- Shuffle: a slight tilt on every letter, typeface on the fraction you choose
- Collision proxies that follow the letterform, not a bounding box
- Lock holds a state still; Reset returns to the grid
- Tilt levels to the pose you were holding when you switched it on

### Output — still and video
- PNG at 1× or 2×, straight to Photos or the share sheet
- Video: count-in, open take, stop when you like, up to sixty seconds
- Recording replays your touches offscreen at full resolution
- Failures surface instead of silently doing nothing

### Library — local only
- One JSON file per composition, reopened straight into the editor
- Grid of thumbnails, delete behind a confirmation
- No accounts, no network, nothing leaves the device

### Widget — app side only
- Pin compositions, rotate every 15, 30 or 60 minutes
- Preview at true small, medium and large dimensions
- Timeline scheduling written and verified in the app target
- The home-screen extension itself needs a paid account

---

## Where the experience is thin

In the order a new user would run into them, not the order they are hard to fix.

**Nothing explains the app** *(first minute)* — Nine controls in the effect bar, tabbed
sheets, eighteen effects, three gestures, and the only guidance anywhere is "Tap the
canvas to type". Almost none of the depth is findable.

**No way to style one letter** *(core promise)* — The one architectural rule was written
to make this possible, and it is the only part of v3's intent still unbuilt. Everything
under it is already in place.

**The typeface list is whatever iOS ships** *(the subject itself)* — A typography app's
face list is its taste. Right now it is a filter over system fonts, and bundling licensed
faces has been marked "a v2 concern" since v1.

**Never profiled on a real device** *(unknown)* — The canvas runs at 60fps continuously,
with shaders and, in Tilt, CoreMotion. Battery and thermal behaviour are invisible in the
simulator.

**The gallery is storage, not a library** *(returning users)* — No rename, no duplicate,
no sort or search. Fine at five compositions, unusable at fifty.

**English only, no string catalog** *(reach)* — Zero localisation files. Not urgent for a
first release, but every hardcoded string written from here makes it more work later.

**No App Store listing exists yet** *(shipping)* — The binary is ready: icon, privacy
manifest, encryption declaration, iPhone portrait, 83 checks green. The listing is not —
no screenshots, subtitle, description or keywords.

---

## Where to start, in order

Ranked by what it does for the experience against what it costs. The first two change what
the app *is*; the rest make it a product.

### 01 · Never open on an empty canvas
*small · editor · first run*

Not a tutorial — a starting composition. First launch lands on something already typed,
already styled with a preset, with one effect live. Every control then has something to
act on, and the depth becomes discoverable by fiddling rather than by being told.

Pair it with a single quiet coach mark on the effect bar the first time only. This is the
cheapest change on the list and the one that most changes the first minute.

### 02 · Per-letter selection
*medium · editor · the plan's last gap*

A mode where tapping a letter selects it, and the style sheet then targets that glyph
instead of all of them. The model, the glyph nodes and the transforms have been ready
since v1; what is missing is a selection state and a target switch in the panel that
already exists.

This is the app's differentiator. Every other text-on-image tool styles a text block;
this one was architected to style a letter.

### 03 · Bundle four to six real typefaces
*small · assets · licence check*

Pick OFL faces with genuine character — a grotesque, a high-contrast display serif, a
mono, something odd — check the licences, drop them in `ATSApplicationFontsPath`. The font
picker already previews your own text, so good faces pay off immediately.

### 04 · Profile on the phone, then idle the canvas
*medium · canvas · device only*

Run Instruments against the real device: frame time, energy, thermal state. Then stop the
canvas rendering at 60fps when nothing is animating — no active shader clock, no
interaction, no tilt. It is the difference between an app that warms the phone and one
that doesn't, and it cannot be seen in the simulator.

### 05 · Make the gallery a library
*small · gallery*

Rename, duplicate, sort by date or name, and "open as a copy" so a saved piece becomes a
starting point rather than something you overwrite. All local, all on the store that
already exists.

### 06 · Give export some choices
*small · export*

3× stills, a video length and quality picker, and social-shaped presets on the aspect
menu. Cheap to build, and it is the moment the user is most invested — they are exporting
because they made something they like.

### 07 · Build the store listing with the app itself
*medium · release*

Typeo renders its own artwork at exact pixel sizes — a small screenshot mode could produce
App Store assets directly, on-brand by construction. Then write the subtitle and
description, and answer the privacy questions, which the manifest already makes trivial:
no tracking, no collection, no network.

### 08 · Widget, the day the account clears
*an afternoon · blocked on account*

Add the target, enable the App Group on both, move `WidgetCompositionView` into it, re-pin
once. The scheduling logic is already compiled and verified inside the app.
`TypeoWidget/README.md` has the four steps.

---

## Constraints worth not relearning

Each of these cost real debugging time at least once. The full set lives in
[CLAUDE.md](CLAUDE.md).

**Shaders fail silently.** An `SKShader` that does not compile is applied as nothing, with
no error. Proof it ran is that pixels moved — compared against a baseline, per pixel.

**Uniform ink has nothing to read.** A luminance LUT, a quantiser and a halftone all did
precisely nothing on flat white text. Three separate bugs, one cause. Shade before you
screen.

**The model only ever gains Optionals.** Swift's synthesized decode has no fallback for a
non-optional. Every field added since v6 is Optional with a `resolved` accessor, which is
why five versions of saved files still open.

**Export parity is hand-maintained.** `SKRenderer` barely steps the scene, so all motion
is integrated by hand and recordings replay touches rather than capture the screen.
Anything new that moves has to enter through the same door.

**Liquid Glass is chrome, never canvas.** `.glassEffect` cannot attach to a SpriteKit node
and would not survive export. The glass in the canvas is a shader that implements the
recipe: lens, frost, rim light, contact shadow.

**Determinism is a feature.** Same input, same pixels — that is what makes a recorded
video match the screen. Hash seeds, dictionary iteration order and frame-rate assumptions
have each broken it once.
