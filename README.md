# Typeo

A native iOS app for making type look interesting. Type something, pick a font,
style it, export it. SwiftUI, local-only, no accounts, no network.

A 30-day learning project, versioned deliberately so each version is additive
rather than a rewrite.

## Status

**v1–v4 shipped, v5 blocked on a paid developer account, v6 (an unplanned UI and shader
overhaul) is now most of the app.** See [STATUS.md](STATUS.md) for the full ledger: what
works today, where the experience is thin, and what to build next.

## Architecture

Every character is its own `Glyph` object from v1 onward, even though v1's UI never
exposes per-character controls. See [CLAUDE.md](CLAUDE.md) for the model and the
version boundaries — that file is the contract.

## Build

Requires Xcode 26+ and iOS 17.0 as the minimum deployment target.

```
open Typeo/Typeo.xcodeproj
```

Then ⌘R.
