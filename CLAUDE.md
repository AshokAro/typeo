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
- Colour editing lives in a right-edge rail (`FillRail`), not a sheet — a sheet covered
  the canvas so you could not see what you were changing.
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
