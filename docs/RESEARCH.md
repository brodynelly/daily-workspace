# Research notes

Two deep-research passes (October 2026): claims were fetched from primary sources and adversarially verified (3 independent votes each). Only confirmed items are listed as facts.

## Confirmed

**Neovide cursor** (official docs, source on `main`, release notes 0.15.0, PR #3061)
- Four corners, each with a relative position, its own critically damped spring and its own duration. Destination per corner = cursor destination + relative position × cursor size.
- Spring uses the exact closed form `x(t) = (a + b·t)·e^(−ωt)`, stable at any `dt`.
- Defaults: `animation_length` 0.150 s, `short_animation_length` 0.04 s, `trail_size` 1.0. Moves of about two cells or less on one row use the short length (typing). Otherwise per-corner length = lerp(trailing, leading, alignment with travel direction).
- 0.15.0 made the cursor front jump immediately and animate only the trail.
- Effects modes: railgun, torpedo, pixiedust, sonicboom, ripple, wireframe (default none).
- MIT licensed. Stack: Rust, winit 0.30, glutin/OpenGL, skia-safe. No `wgpu`.
- **Not confirmed (refuted):** that ω = 4/(ζ·length) settles within 2 % in `animation_length`. This project uses its own ω = 6/length.

**macOS**
- macOS 14+: standard `NSTextView` uses the system text cursor (`NSTextInsertionIndicator`). No spring/glide API exists, so a smooth caret needs a custom overlay (our inference).
- EventKit has no read-only grant: use `requestFullAccessToEvents` and enforce read-only in code. Needs `NSCalendarsFullAccessUsageDescription`.
- FSEvents is the right primitive for watching a vault tree. (This app polls snapshots every 2 s plus on activation instead; simpler, and enough for one open note.)

**Licensing**
- Monkeytype is GPL-3.0: reimplement behaviour, do not copy code.

## Not verified

- Monkeytype's actual caret source, durations and per-character classes.
- Neovide's effects files, scroll animation and render loop.
- Zed/GPUI, Lapce and other reference projects' licenses.
- Tauri + CodeMirror 6 vs Rust + Skia vs SwiftUI as a full comparison.

## Decision

Mac first → Swift + SwiftUI + AppKit (`NSTextView` hosts the editor, a custom overlay draws the caret). If Windows ever becomes a requirement, the better path is Tauri + CodeMirror 6, porting `CaretAnimator` to TypeScript (it is ~100 lines of pure maths).
