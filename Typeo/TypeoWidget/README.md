# TypeoWidget — v5, waiting on a paid Apple Developer account

This folder holds the finished widget extension source. It is **not compiled** yet:
it sits outside `Typeo/Typeo`, which is the app target's synchronized group.

## Why it is not wired up

A widget extension runs in its own sandbox. It can only read the app's files through
an **App Group**, and App Groups require a **paid Apple Developer Program membership**
($99/year). A free Personal Team cannot enable that capability.

Everything else in v5 is built and working today:

- `TypeoSharedStore` — the seam. Returns the App Group container when it exists and the
  app's own Documents directory when it does not. **No code changes when the account
  arrives.**
- `WidgetPayload` — the manifest written by the app and read by this extension.
- `WidgetTimelinePlan` — the rotation schedule, as pure logic, verified in the app.
- `WidgetPinStore` — pinning, unpinning, rotation, PNG rendering.
- `WidgetCompositionView` — the exact view this extension renders.
- The in-app **Widget** tab previews all of it at real widget dimensions.

## Steps once you have the paid account

1. **Xcode → File → New → Target → Widget Extension.**
   - Product Name: `TypeoWidget`
   - Uncheck "Include Live Activity" and "Include Configuration App Intent"
     (this is a `StaticConfiguration` widget).
   - Let Xcode create the folder, then replace its generated Swift file with
     `TypeoWidget.swift` from here.

2. **Add the shared files to the new target's membership** (File Inspector →
   Target Membership → tick `TypeoWidget`):
   - `Shared/TypeoSharedStore.swift`
   - `Shared/WidgetPayload.swift`
   - `Shared/WidgetTimelinePlan.swift`
   - `Widget/WidgetCompositionView.swift`
   - `Model/Composition.swift` (only for the `AspectRatio` enum the payload stores)

3. **Enable the App Group on BOTH targets.**
   - Target `Typeo` → Signing & Capabilities → + Capability → App Groups → add
     `group.Aro.Typeo`
   - Target `TypeoWidget` → same capability → same group.
   - The identifier must match `TypeoSharedStore.appGroupIdentifier`.

4. **Re-pin once.** Anything pinned before the App Group existed was written to the
   app's Documents directory, which the widget cannot see. Open the Widget tab; the
   status card will say "Ready for the widget". Then re-add your compositions.

5. Long-press the home screen → add the Typeo widget.

## Reality check

The widget shows a **finished, already-rendered PNG** on a timeline. It cannot animate,
cannot run the shaders, and cannot run the physics canvas — WidgetKit does not allow
it. Rotation is capped by the system too: WidgetKit treats a timeline as a budget, so
15 minutes is the practical floor and the OS may still be slower.
