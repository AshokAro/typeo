# CLAUDE.md — Typeo

## Project
Native iOS app, SwiftUI, local-only (no accounts, no network). A canvas where the user
types text, picks a font, styles it, and exports an image to Photos / the share sheet.
30-day learning project, versioned deliberately so later versions are additive, not rewrites.

Xcode project lives at `Typeo/Typeo.xcodeproj`. Repo root is `~/Documents/Typeo`.
Minimum deployment target: **iOS 26.0** (required for Liquid Glass: `.glassEffect`,
`GlassEffectContainer`, `.buttonStyle(.glass)`). `.layerEffect` Metal shaders are iOS 17+
and remain available, so the v2 shader plan is unaffected.

## THE ONE ARCHITECTURAL RULE — do not violate

Every character is its own object from v1, even though v1's UI does not expose
per-character controls. Define `Composition` in v1 and never reshape it:

```
Composition
- id, createdAt
- aspectRatio (1:1 | 9:16 | 16:9)
- background (color/gradient)
- globalShader          // v1/v2: one shader applied to the whole block
- glyphs: [Glyph]
    - character
    - font
    - size
    - color
    - positionOffset    // x, y — default (0,0) in v1
    - rotation          // default 0 in v1
    - shaderOverride    // nil in v1
```

v1's UI only ever writes the SAME value to every glyph at once. v3's per-letter mode
starts writing DIFFERENT values to individual glyphs. The model does not move.
This is what makes v1 -> v3 additive instead of a rewrite.

If a change would require reshaping `Composition`, stop and flag it before writing code.

## Core loop (never changes across versions)
Launch -> blank canvas -> type text -> pick font -> style it -> export/share.
Nothing added later should touch how text gets *typed in* or *exported out* —
only what happens in between.

## Version boundaries — stay inside the current one

- **v1 (DONE)**: type -> curated font list -> single color + one Core Image filter ->
  3 aspect ratios -> export image -> Photos + share sheet.
  EXCLUDED: multiple shaders, per-letter anything, video, widget, gallery/persistence, accounts.
- **v2** (DONE): full shader set (bloom, heat, noise, glitch) as Metal shaders on the
  text block. In-app gallery with local persistence of `Composition` as JSON.
  EXCLUDED: per-letter divergence, video, widget.
- **v3** (DONE): canvas rebuilt as individually addressable SpriteKit glyph nodes.
  Per-letter jumbling. Tap-and-hold: inflate, float, gravity/drop.
  EXCLUDED: video, widget.
- **v4** (DONE): offscreen frame-by-frame render of v3 animations + `AVAssetWriter`
  encoding, saved to Photos or shared. EXCLUDED: widget.
- **v5** (app side DONE, extension BLOCKED on a paid account): pin compositions to a
  shared manifest, rotate them on a timeline, preview at real widget sizes in-app.
  The WidgetKit extension target itself needs an App Group, which needs a paid Apple
  Developer Program membership. Source is written and waiting in `Typeo/TypeoWidget/`.
  Widgets CANNOT run the live shader/physics canvas — they show a finished PNG.

## Screen flow
1. Splash — static asset, ~1s, no loading logic (nothing to load, local-only)
2. No onboarding, no login — straight into the editor on first launch
3. Editor/Canvas — tap to type; aspect switcher always visible; font picker with live
   preview on the user's ACTUAL typed text (not sample text); style panel
4. Export — render canvas to image at the selected aspect ratio, save to Photos,
   share via generic `UIActivityViewController`
5. (v2+) Gallery tab · (v3) per-letter mode toggle · (v4) Record

## Conventions
- SwiftUI only for UI. No third-party dependencies unless explicitly agreed.
- **Liquid Glass is chrome only.** `.glassEffect`, `.buttonStyle(.glass)` and friends belong
  on control panels, buttons and toolbars — NEVER on the canvas. The canvas is content and
  gets exported; glass is UI and never does. Keep that boundary hard: it is what keeps the
  export path clean from v1 through v4.
- The canvas lays out at a fixed reference size per aspect ratio (1080x1080, 1080x1920,
  1920x1080) and is scaled down for on-screen display. Preview and export therefore run the
  SAME view at the SAME logical size — WYSIWYG is structural, not maintained by hand.
- Shaders are SwiftUI modifiers (`.colorEffect` / `.distortionEffect` / `.layerEffect`)
  applied to the TEXT BLOCK, never the background and never the chrome. `ImageRenderer`
  captures all three modifier types (verified), so the live canvas and the exported file
  run the same modifier. Never approximate an effect live and filter only on export.
- Animated shaders read a `time` value passed into `CompositionCanvas`, not stored on
  `Composition`. The editor drives it from one clock shared with the exporter, so an
  exported frame is the frame that was on screen. v4's video export is this same call
  in a loop over `time`.
- Metal shaders need the Metal Toolchain component: `xcodebuild -downloadComponent MetalToolchain`.

## v3 SpriteKit findings — do not relearn these

- `ImageRenderer` CANNOT capture `SpriteView`; it renders SwiftUI's "unsupported view"
  placeholder (a yellow square with a red no-entry sign). Export therefore goes through
  `SKRenderer` into an offscreen Metal texture.
- `SKView.texture(from:)` ignores `contentScaleFactor` and outputs at the SCREEN scale
  (3240px on a 3x device), so export size would depend on the device. `SKRenderer` with
  an explicit viewport gives exact sizes. Use it.
- `SKLabelNode` SILENTLY falls back to Times when given the system font's PostScript
  name (".SFUI-Semibold"). It reports a non-zero width, so it looks like it worked.
  Glyphs are therefore rendered through UIKit (`GlyphTextureFactory`) and handed to
  SpriteKit as textures, which also keeps metrics identical to v1/v2 so saved
  compositions do not reflow.
- Glyph textures are drawn WHITE and tinted per node, so a colour change does not
  re-render the texture.
- SKShader uses a GLSL ES subset, NOT Metal. v2's `.metal` shaders were rewritten in
  `SpriteShaders.swift`; `u_texel` (1/textureSize) is supplied so offsets stay in pixels.
- The global shader lives on an `SKEffectNode` wrapping the glyph nodes, with a clear
  canvas-sized sprite inside it so a glow or tear is not clipped at the block's edge.
- `SKRenderer.update(atTime:)` advances the SHADER clock but does NOT reliably step the
  scene — measured at 2 scene updates across 60 render calls. SpriteKit's own physics
  therefore barely moves during an offscreen recording while running normally in a live
  SKView, which would make a recorded drop differ from the drop on screen. Motion is
  integrated by hand in `GlyphScene.advance(to:)`, called by BOTH the live scene's
  update and the offscreen frame renderer. Do not reintroduce `SKPhysicsBody` for
  anything that has to appear in an export.

## v6 UI notes

- The canvas uses `.rect(cornerRadius: 28, style: .continuous)` — the iOS squircle.
  Rounding is CHROME ONLY: the exported PNG stays square-edged, or shares would carry
  transparent corners.
- Adding a NON-OPTIONAL field to `Composition` breaks every saved file: Swift's
  synthesized decode uses `decode(_:forKey:)` with no default fallback. New fields must
  be Optional (which decodes via `decodeIfPresent`) or ship a custom `init(from:)`.
  `textGradient` is Optional for exactly this reason, and there is a regression test
  that decodes a hand-written pre-v6 JSON.
- One `SKEffectNode` cannot stack two shaders. The text gradient runs on an INNER
  effect node holding the glyphs; the FX shader runs on the OUTER one.
- `textGradient` set means the gradient spans the block and overrides per-glyph
  colours; nil means each glyph uses its own colour, so v3's per-letter colour
  divergence still works.
- `CGContext.drawLinearGradient` must be given `.drawsBeforeStartLocation` and
  `.drawsAfterEndLocation`, or an oblique angle leaves the canvas corners unpainted.
- Colour editing lived in a right-edge rail (`FillRail`) because a sheet covered the
  canvas. SUPERSEDED in Stage D: fill and effect are back in the style sheet, and the
  canvas shrinks into the space above the open sheet instead. See the Stage D notes.
- Don't wrap a fixed-size glass control in `GlassEffectContainer`; it is for morphing
  between glass shapes and sized the rail's capsule to the wrong bounds.

## v6 Stage B notes

- Text is edited ON the canvas. A `UIKeyInput` view (`KeyInputBridge`) supplies
  insertText/deleteBackward and nothing else; the caret index and the caret node are
  ours. A UITextField would mean mirroring a hidden field's selection onto the canvas.
  Cost: no autocorrect or dictation, which suits a typography canvas.
- Edits are insert/delete at a caret index, NOT setText. That keeps the glyph ids
  either side of the caret stable, so per-letter styling survives editing —
  setText's positional reconcile could not guarantee that.
- Taps reach the SpriteKit scene directly. Do NOT put a SwiftUI `onTapGesture` on the
  canvas container; it swallows the touches the scene needs for caret placement.
- `float` was absorbed into `attract` at strength 0 (zero gravity). Modes are now
  none / bloat / pucker / attract / drop, each with one 0...1 amount.
- Alignment, letterSpacing and lineHeightMultiple are Optional for the same decode
  reason as textGradient; `resolved*` accessors supply the pre-v6 defaults, and there
  is a test asserting an old file renders byte-identically.

## v6 Stage C notes

- **SKShader failures are SILENT.** A shader that does not compile is simply not
  applied and SpriteKit says nothing. Worse, setting any shader flips
  `shouldEnableEffects`, which changes rasterisation by a pixel or two — so "output
  differs from baseline" is NOT proof a shader ran. Verify by mean ink colour or by
  geometry change.
- What broke them: an early `return` inside `main()`, and an extra helper function
  beyond the shared noise ones. Write shaders with no early return, no if/else-if
  chains (use `mix`/`smoothstep`), and only the shared helpers.
- Colour is premultiplied. Divide by alpha to read true RGB, multiply back on output,
  and never modify alpha or the glyph edges fringe.
- Interaction modes are now none / warp / attract / gravity. Warp and gravity are
  BIPOLAR: 0 does nothing, negative puckers / floats up, positive bloats / falls down.
- The gravity ceiling mirrors the floor. Wrapping letters around to the bottom read as
  a glitch.
- `isLocked` on the scene suppresses spring-back on release, so a state can be held for
  a screenshot or an export.
- Background lives on its own node, so `applyAppearance` must rebuild it. Previously a
  background colour change only appeared once something else forced a full rebuild.
- Video records TOUCHES and replays them offscreen rather than capturing the live view.
  Capturing the view is pinned to the screen's scale and drops frames; replay is
  deterministic because motion is integrated in `advance(to:)`.

## v6 shader library (current)

- Shader KIND raw values are never removed, only reimplemented. `chrome` now renders
  liquid metal and `thermal` renders a heatmap; deleting the cases would fail to decode
  every saved composition, because Kind is a non-optional String enum.
- Effects run on the TEXT and on the BACKGROUND independently:
  `Composition.globalShader` and `Composition.backgroundShader` (Optional, additive).
  The background has its own `SKEffectNode` wrapping the background sprite.
- Generative shaders (mesh, grain, dither, gem smoke) respect source alpha, so the same
  code works as a background fill and as a tint on the glyphs.
- Things that made shaders look wrong, all found by looking at renders:
  - A luminance LUT does nothing on uniformly white text. Heatmap builds its heat field
    from BLURRED ALPHA instead, so there is a gradient to map.
  - A plain golden-angle spiral makes glow taps line up into visible rings. Neon jitters
    each tap's angle.
  - Cross-fading two OPPOSITE palettes lands on grey at the midpoint. Mesh rotates hue
    instead, so the field stays saturated at every slider position.
  - Inverse-square weighting averages a multi-point gradient toward grey. Mesh uses
    fourth-power falloff to keep the colour zones distinct.
- A `DragGesture` on a container swallows taps meant for buttons inside it. The tool
  rail's drag lives on its handle alone.

## v6 interaction rules (current)

- EVERY interaction slider is bipolar, -1...1, and rests at 0 doing nothing:
  warp = pucker/bloat, attract = push/pull, gravity = float up/fall down,
  tilt = uphill/downhill.
  Shuffle stays 0...1 because a negative percentage is meaningless.
- Shuffle has TWO axes. Tapping it TILTS every letter slightly and the slider says how
  many additionally get a new TYPEFACE and a small size change — so a shuffle at 0
  still tips the line without touching the type. The readout says "restyled" for that
  reason. Shuffle does NOT move letters: displacing them broke the word up, and moving
  letters around is what Attract is for.
- The slider UI must read `mode.amountRange`. Hardcoding `0...1` in `sliderRow` is what
  made pucker and float-up unreachable even though the model already allowed them —
  the range existed and nothing used it.
- At amount 0 a mode must be completely inert, wander included. Scale any idle motion
  by the amount rather than running it unconditionally.
- Releasing a touch restores the state captured at touch-DOWN
  (`preInteractionState`), not the laid-out grid. A shuffle applied beforehand must
  survive the gesture; only what the effect did is undone. `reset()` is the one that
  goes back to the grid.
- Attract has a soft boundary at 22% of the canvas beyond each edge. Without it, push
  at -100% threw the letters ~2200px out on a 1080 canvas and they simply vanished.

## v5 widget notes

- `TypeoSharedStore` is THE SEAM. It returns the App Group container when the
  capability exists and the app's own Documents directory when it does not, so
  **no code changes when the paid account arrives** — only entitlements.
- A widget extension has its own sandbox and can ONLY read the app's files through an
  App Group. A free Personal Team cannot enable that capability, which is the entire
  reason the extension target does not exist yet.
- `Typeo/TypeoWidget/` sits OUTSIDE the app target's synchronized group (`Typeo/Typeo`)
  on purpose, so its source does not compile into the app. `TypeoWidget/README.md` has
  the exact steps to wire it up.
- Scheduling lives in `WidgetTimelinePlan`, in the app target, so it is compiled and
  verified today; the extension's `getTimeline` only maps its slots and loads images.
- WidgetKit will not honour a rotation faster than roughly 15 minutes. The plan clamps
  rather than pretending.
- Anything pinned before the App Group exists is written where the widget cannot see
  it. Re-pin once after enabling the capability.

## v4 video notes

- `CompositionFrameRenderer` holds ONE scene, SKRenderer and Metal objects for a whole
  recording and just advances the clock. Building a fresh scene per frame (what the
  still exporter does) would restart the animation every frame.
- Frames render straight into CVPixelBuffer-backed Metal textures via
  `CVMetalTextureCache`, so `AVAssetWriter` consumes them with no CPU copy.
- H.264 requires even pixel dimensions — the frame renderer rounds to even.
- Video renders at scale 1 (1080 wide). Scale 2 doubles encode time for no visible gain
  on a phone.
- Export renders via `ImageRenderer` (SwiftUI) at the target aspect ratio and scale.
- Photos save requires `NSPhotoLibraryAddUsageDescription` in Info.plist.
- Bundled fonts must be OFL/licence-checked and declared in Info.plist under
  `ATSApplicationFontsPath` / `UIAppFonts`.

## Build / run
Prefer XcodeBuildMCP tools when available. CLI fallback:
```
xcodebuild -project Typeo/Typeo.xcodeproj \
  -scheme Typeo -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## v6 Stage D notes (current)

### Panels
- Fill and effect both live in the style sheet under ONE top-level Text / Background
  tab. The old objection — a sheet hides the artwork — is answered by shrinking the
  canvas into the room above it: the sheet has two detents (0.45 / 0.7, capped at 70%)
  and the editor TRACKS which one is showing, because `PresentationDetent` cannot be
  asked for its fraction. The canvas factors are measured against the chrome, not
  derived from the detent: the canvas area already excludes the top bar.
- A sheet over this app must set `.presentationBackground` to something OPAQUE. The lit
  mode pills behind it smeared through the default material and read as a stain.
- The type sheet holds size and block layout as well as the typeface, so selecting a
  face no longer dismisses it.
- The floating tool rail is gone. Lock and collision are toggles in the effect bar.

### Layout traps
- A `ScrollView` in an `HStack` beside a fixed group gets squeezed NARROWER than its own
  content, and with `.scrollClipDisabled()` the overflow draws straight over the
  neighbour — the shuffle pill rendered on top of the lock. One row, one scroll view.
- Eight pills only fit at `.controlSize(.small)` with 20pt icon frames. `.buttonStyle(.glass)`
  carries ~14pt of padding a side, which dominates the icon size.
- `Slider` has no detent. Bipolar sliders snap to 0 inside ±0.05 in the BINDING, with a
  haptic on the way in.

### Scene
- `applyAppearance` must push `positionOffset` and `rotation` onto the nodes, or a
  shuffle that only scatters cannot reach the screen at all. But push only what
  CHANGED (`appliedTransforms`): re-applying every time would snap a held drop back to
  the grid the moment an unrelated colour changed.
- `GlyphScene` is not observable, so it cannot be ASKED whether an effect is showing.
  It reports via `onInteractionBegan`, which is what enables Reset for scene-only state
  like a locked drop.
- Collision is hand-integrated (circle proxies, overlap split, velocity bled off), for
  the same reason as everything else here: `SKPhysicsBody` barely steps under
  `SKRenderer`. Pairs are walked over a STABLE ID ORDER — resolving in dictionary hash
  order would make a recording diverge from the same touches on screen.
- The collision radius is half the NARROW side of a glyph. A glyph texture is its
  advance box, so half the wider side would have neighbours shoving each other apart at
  rest; measured drift on normal text is 0.

### Shader findings
- `SKEffectNode.filter` WORKS under `SKRenderer` (verified), the CIFilter radius scales
  with the SCENE and not the raster (so a 2x export matches the screen), and `filter`
  runs BEFORE `shader` — the shader is handed the already-filtered texture.
- That is how neon and heatmap get a real halo: a second layer of glyph COPIES under
  the crisp text, carrying a `CIGaussianBlur`, coloured by a field shader. A ring of
  taps in one pass reproduces the glyph at every tap, which is exactly what "pinpoints
  of light" and "the text repeated a bunch of times" were.
- Flat white text is a FIXED POINT of a quantiser: dithering compiled, ran, and changed
  nothing. It now shades before quantising. Same family as the luminance LUT that made
  the old heatmap inert — if an effect reads the ink and the ink is uniform, it has
  nothing to read.
- Neon's hue ROTATES around the circle. Crossfading cyan to magenta lands on grey in the
  middle, the same trap the mesh gradient hit.
- Liquid metal's Flow multiplies the clock, so 0 is a still image. `SKRenderer.update(atTime:)`
  does NOT advance the shader clock offscreen either — the freeze was verified by
  driving `u_time_offset` directly, not by rendering two scene times.
- Glass refracts the background FILL, handed in as `u_background`. It CANNOT see the
  background SHADER's output — that lives on another effect node and is not available
  as a texture — so a shadered background shows through the letters as a different
  image from the one around them. Do not pair the two; the Glass preset does not.
- `.glassEffect` can never do this: it is a SwiftUI modifier, it cannot attach to a
  SpriteKit node, and `SKRenderer` would not capture it. The shader implements the
  recipe instead — lens, frost, rim light, contact shadow.
- Retiring an effect means hiding it from `Kind.selectable`, never deleting the case.
  Gem Smoke is retired and still renders for anything already saved.

## v6 Stage E notes (current)

### Model additions (both additive, nothing reshaped)
- `ShaderEffect` gained `tertiary: Double?` and `variant: Int?`, so an effect can offer
  three sliders and a discrete choice. Optional, so files written before them decode.
- `Background` gained `case image(id: String)`. Codable keys an enum on its CASE NAME,
  so adding a case leaves old files decoding unchanged. The pixels are NOT in the
  model: `BackgroundImageStore` holds the file and the JSON carries an id. Undo
  snapshots whole Compositions, so embedded image data would be copied on every
  keystroke.

### Effect controls
- Each kind declares its own `controls` (and optional `variants`), and the style panel
  builds itself from that list. One hardcoded "secondary" row could not express
  "temperature AND intensity AND speed".
- Adding a uniform to the shared list is free; REFERENCING a uniform that was not
  supplied is what silently kills an SKShader. `u_tertiary` and `u_variant` are always
  supplied, `u_glyphs` and `u_background` only for the shaders that name them.
- A discrete variant is selected in GLSL by weights (`step(abs(u_variant - n), 0.4)`),
  never an if/else chain — see the Stage C rule about what stops a shader compiling.

### Shaders
- Matrix rain needs actual CHARACTERS and a fragment shader cannot draw type:
  `MatrixGlyphAtlas` renders 64 katakana/digits into an 8x8 texture handed over as
  `u_glyphs`. Cells are FIXED to the canvas and the brightness falls down them —
  scrolling the sampling coordinate instead makes the glyphs slide, which the film
  never does.
- The rain is only visible INSIDE the letters, so it needs a dim ambient floor and no
  gap in the head cycle; with film-accurate sparseness most of the word was black.
- The mesh gradient's SHAPE was the one fixed thing about it. The variant seeds where
  the colour centres sit and how fast they travel; the dice reseeds it.

### Collision
- `GlyphShapeFactory` rasterises each glyph into a coverage grid (6 rows) and covers the
  ink with circles, so a T is a crossbar and a stem rather than a disc. Verified by
  printing the proxy as ASCII — which is also how the bitmap's orientation was checked.
- Circle radius is exactly half a cell and overlaps shallower than 8% of a pair's reach
  are ignored. Anything more generous and switching collision on nudged a normally
  spaced word apart before anything had moved (measured: 7pt of drift).
- UIKit text drawing needs `UIGraphicsImageRenderer`'s flipped context. Drawing into a
  bare `CGBitmapContext` renders the glyph upside down, which a coverage grid will
  happily accept without complaining.

### Elsewhere
- The widget picker sheet existed and was never presented: `showPicker` was set and
  nothing observed it. Setting state that no `.sheet` is bound to fails silently.
- `ColorPicker`'s rainbow-ringed well is replaced by `ColorWell` — the same UIKit
  picker (`UIColorPickerViewController`) behind a plain swatch of the actual colour.

## v6 Tilt notes (current)

- Tilt is the GRAVITY integrator with a direction vector instead of a fixed down. It is
  not a new physics system, which is why it composes with collision for free: letters
  slide into the low corner and pile up on their letter shapes.
- **Measured relative to the pose the phone was in when the mode was selected.** Nobody
  holds a phone flat, so absolute gravity dumps every letter into the bottom of the
  canvas the instant Tilt is chosen. `TiltSource` captures a reference on start;
  tapping the Tilt pill again re-levels, and so does Reset.
- The IN-PLANE part of gravity is the slope of the screen — flat on a table correctly
  has no downhill at all. Subtracting the reference makes leaning back past the
  reference read as uphill, which is what makes the control symmetric.
- No usage description is required: only motion ACTIVITY (the pedometer) asks
  permission, not the accelerometer or gyroscope. `CMMotionManager` runs ONLY while the
  mode is selected and the scene is active.
- Tilt rides in the SAME recording track as touches, sampled every frame rather than
  throttled. Verified: a replay reproduces a live 3-second wobble with 0.0000pt of
  drift. A separate track could drift out of step with the touches.
- Stills export through `CompositionRenderer.render(..., tilt:)`. Rendering at zero
  would silently drop the parallax and un-swing the light, so the file would differ
  from the preview — the one thing the canvas contract forbids.
- Rebuilding a shader resets its uniforms, so `applyShader` pushes the current lean back
  on. Live that self-corrects on the next reading; a still export renders exactly one
  frame and would not.
- Background parallax moves the background NODE (4.5% of the canvas, node oversized so
  no edge appears), and the glass shader is told the same shift through `u_bg_shift` —
  otherwise the letters refract a background that is no longer behind them.
- The collision clamp now uses each glyph's half-extents, not its bounding radius. The
  bounding radius is half a diagonal, so it held letters further from the edge than the
  interaction modes did, and the two clamps fought every frame — a corner pile stayed
  permanently overlapped. Six relaxation passes, and a settled pile still shows ~4pt of
  contact tolerance, which is what an impulse solver under constant pressure does.
- `.buttonStyle(.glass)` carries ~23pt of fixed padding per pill and IGNORES
  `controlSize`, so the icon frame is the only lever on how many controls fit a row.
  Nine fit at 17pt with a spacer instead of a divider. A tenth has to live elsewhere.

## v6 recording, photo and shader-control notes (current)

### Recording
- Recording is a 3-2-1 count-in and then an OPEN take the user ends with a Stop button
  in the recording pill. A fixed length meant composing the whole performance before
  pressing the button. The take is capped at 60s because the export renders a frame at
  a time.
- The countdown numeral is backed by a dark circle: it sits ON the artwork, and a bare
  numeral disappears into whatever is already there.
- The recording pill must NOT be inside an `allowsHitTesting(false)` overlay any more —
  it now carries the control that ends the take.

### Hit testing
- `.clipped()` stops a fill-scaled image DRAWING outside its frame but not HIT-TESTING
  outside it. The widget preview was wrapped in a button, so with a composition pinned
  that button had an invisible hit area the size of the overflowing image, covering the
  size picker above it — which is why Large could not be chosen once something was
  pinned. `.contentShape(.rect)` bounds it; the preview is no longer a button at all.

### Photo backgrounds
- A segmented fill mode derived PURELY from the model can contain a state the model
  cannot yet express. The Photo tab could never be opened: there was no image, so the
  segment snapped back to Solid and the picker was unreachable. The panel now tracks
  the tab being BROWSED separately, and follows the model when a preset changes it.
- `BuiltInBackgrounds` draws its six photos rather than bundling them: no asset weight,
  no licence to check, and a composition saved with one still opens on a device that
  has never seen it, because there is no file to go missing. Ids are namespaced
  `builtin:` so the store can tell them from a picked photo.

### Canvas overlays
- Anything drawn OVER the canvas belongs inside `CanvasStage`, sized in REFERENCE points
  and multiplied by `displayScale` — the same rule the canvas itself follows. The empty
  hint was a sibling in the editor's ZStack, so it kept a fixed size and stayed centred
  in the whole area while the canvas shrank under a sheet or changed aspect. Its scale
  is floored, because 16:9 shrinks the canvas far enough that a strictly proportional
  instruction stops being readable.

### Effect controls
- `EffectControl` carries its own RANGE, so an individual slider can be bipolar (lens
  distortion: barrel one way, pincushion the other) while the rest stay 0...1. Bipolar
  effect sliders get the same snapping and centre tick as the interaction ones.
- Halftone: the dots are a metaball field, which is what lets a Gooey control merge
  them. Two things had to be right — the falloff must be FOURTH power (with a square
  falloff eight neighbours alone exceed the threshold and every cell reads as solid
  ink), and the source must be SHADED first, because a halftone of uniform white is
  solid white. Same family as the dither and the luminance LUT.
- Lens distortion: only a pincushion samples outside the texture, so only that
  direction is normalised back onto the corner. Normalising both ways magnified the
  barrel until the picture was a stamp in a black field.
- Fluted glass treats each rib as a cylindrical lens with a specular crown and a dark
  seam. It is a BACKGROUND effect in spirit — it needs something behind it worth
  bending.

## Testing and release readiness (current)

### The test surface
- `Diagnostics/SelfCheck.swift` is the app's test suite: 83 checks over the model,
  store, layout, canvas, every shader, every interaction, collision, caches,
  backgrounds, the library, the widget manifest and export. DEBUG only — verified
  absent from the Release binary — and run with `-selfCheck` on the launch arguments.
- There is no unit-test target on purpose: the parts worth testing (shaders, the
  SpriteKit canvas, the export path) only behave correctly inside a real Metal context,
  and every bug worth catching here was caught by rendering something and measuring it.
- A shader check must compare renders PIXEL BY PIXEL against a baseline. A whole-frame
  mean is dominated by the background, which the text shaders never touch — measured as
  seven shaders "unchanged" that were all working.

### Bugs the audit found
- Deeply interlocked glyphs could stay permanently overlapped with collision on:
  resolving one contact recreated an equal one on another face and the pair rocked
  between them forever. `contact` now falls back to the line between the glyph centres
  when penetration is deeper than a proxy circle's radius.
- `seedValue` used `hashValue`, which Swift seeds PER PROCESS: the same saved
  composition tumbled differently every launch, and a recording could not be reproduced
  in a later session. It now derives from the UUID's own bytes.
- The glyph texture cache grew without bound — one texture per character per size, and
  the size slider passes through 190 sizes. All three caches are now bounded, with a
  check that drags the whole range and asserts the bound.

### Release settings
- iPhone, portrait only (`TARGETED_DEVICE_FAMILY = 1`). The editor is a vertical stack
  of bars around a canvas and the sheets take 70% of the height; iPad and landscape
  would need a different layout, and shipping them unverified invites a rejection.
- `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect stops asking every build.
- `PrivacyInfo.xcprivacy` declares no tracking, no collected data and no required-reason
  APIs — which is accurate: there is no network code and no third-party SDK.
- The app icon is generated by a script, not hand-drawn, and lives in the asset catalog
  in light, dark and tinted variants.

### Accessibility rules
- The canvas is a `SpriteView`, which is OPAQUE to VoiceOver. It is published as a
  single element with a label describing the composition and an action that starts
  editing — without that the app's central surface simply is not there.
- Selection is shown by tint alone, so every selectable pill also carries
  `.isSelected`; every slider carries a label and a spoken value.
- Reading surfaces use text styles and scale with Dynamic Type. The editor chrome keeps
  fixed sizes (icon controls do not reflow) but is capped at `.accessibility1` so the
  bars cannot push the canvas off screen. The CANVAS never scales with Dynamic Type —
  it is artwork with a fixed reference size, and scaling it would break export fidelity.
- Chrome animation goes through one `chromeAnimation` property that returns nil under
  Reduce Motion, rather than being decided at each call site.
- Control rows are 44pt tall. `.buttonStyle(.glass)` ignores `controlSize`, so the icon
  frame is the only lever on both hit size and how many fit a row.
