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
- **v4**: offscreen frame-by-frame render of v3 animations + `AVAssetWriter` encoding.
  EXCLUDED: widget. First candidate to cut if time runs short.
- **v5**: WidgetKit extension showing a finished, already-exported composition on a
  timeline. Widgets CANNOT run the live shader/physics canvas. Scope small.

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
