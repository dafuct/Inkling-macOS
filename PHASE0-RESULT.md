# Phase 0 Result — 2026-06-23 — GO

Tested on macOS 26.5, Apple Silicon. App: **Inkling** (dev build, ad-hoc signed, `dev.makar.inkling`).

| Check | App | Result | Notes |
|---|---|---|---|
| (a) Overlay ghost text at caret | TextEdit | **PASS** | Gray ` hello` rendered at the caret (confirmed visually) |
| (b) AX text + caret bounds | TextEdit | **PASS** | Overlay positioned correctly; end-of-text fallback works |
| (c) Tab swallowed + suggestion inserted | TextEdit | **PASS** | Tab inserts ` hello` into the document |

**Gate decision: GO** — the system-wide plumbing (CGEventTap + Accessibility + overlay + key-synthesis insert) is proven feasible. The remaining work is ordinary app logic.

## Issues found & resolved during the spike
- Swift 6 strict concurrency vs. unannotated C frameworks → Inkling target builds in Swift language mode 5.
- `kAXSecureTextFieldRole` not bridged into Swift → check role AND subrole against the literal `"AXSecureTextField"`.
- `AXBoundsForRange` fails at end-of-text → fall back to the preceding character's trailing edge.
- A conflicting commercial autocomplete app was installed → dev app renamed to Inkling to avoid TCC/process/Tab clashes.
- Unified-log redaction hid `NSLog` content → diagnosed by running the binary directly so stderr was unredacted.

## Known limitations / carry into Phase 1
- Overlay coordinate flip uses the primary screen only (multi-monitor TODO).
- Ad-hoc signature → Accessibility grant resets on every rebuild (set up a stable self-signed identity).
- `EventTapController` has no `stop()`/teardown; force-casts in `FocusContextProvider`; surrogate-pair edge in `TextContext.prefix`.
- Dummy engine returns a fixed ` hello` (real MLX engine is Phase 2).
