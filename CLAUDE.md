# CLAUDE.md — Typeo

## Project
Native iOS app, SwiftUI, local-only (no accounts, no network). A canvas where the user
types text, picks a font, styles it, and exports an image to Photos / the share sheet.
30-day learning project, versioned deliberately so later versions are additive, not rewrites.

Xcode project lives at `Typeo/Typeo.xcodeproj`. Repo root is `~/Documents/Typeo`.
Minimum deployment target: iOS 17 (required for SwiftUI `.layerEffect` Metal shaders).

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

- **v1 (MVP)**: type -> curated font list -> single color + one Core Image filter ->
  3 aspect ratios -> export image -> Photos + share sheet.
  EXCLUDED: multiple shaders, per-letter anything, video, widget, gallery/persistence, accounts.
- **v2**: full shader set (heat, noise, glitch) via `.layerEffect`/Core Image on the whole
  text block. In-app gallery with local persistence of `Composition`.
  EXCLUDED: per-letter divergence, video, widget.
- **v3**: rebuild canvas as individually addressable glyph nodes (SpriteKit). Per-letter
  jumbling. Tap-and-hold effects: inflate, float, gravity/drop. Biggest single lift.
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
