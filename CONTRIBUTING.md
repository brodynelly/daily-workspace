# Contributing

## Prerequisites

- macOS 14+ with Xcode 16+ command line tools (Swift 6 toolchain; the package builds in the Swift 5 language mode with complete concurrency checking).
- [swift-format](https://github.com/swiftlang/swift-format), which ships with the Swift 6 toolchain (Xcode 16+) as `swift format`.
- [SwiftLint](https://github.com/realm/SwiftLint) 0.65.1, the version CI pins (by checksum) in `.github/workflows/ci.yml`. `brew install swiftlint` works if the versions match.

## Local loop

```sh
swift build
swift test
swift format --in-place --recursive Sources Tests Package.swift   # format
swift format lint --strict --recursive Sources Tests Package.swift  # what CI checks
swiftlint --strict
./scripts/build_and_run.sh --verify                               # bundle, launch, confirm it runs
```

Formatting is owned by swift-format (`.swift-format`: 4-space indentation, 120 columns). SwiftLint (`.swiftlint.yml`) checks semantics only; layout rules that swift-format handles are turned off there. Don't silence a SwiftLint rule without a comment explaining why (see the `force_try` exception in `MarkdownEditor.swift`).

`.codex/environments/environment.toml` runs `scripts/build_and_run.sh` for Codex's Run action.

## Where code goes

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first. In short:

- **New screen or feature:** a `Features/<Feature>/` folder holding its views, its store (an `ObservableObject`), and its service. Add a case to `AppSection` if it gets a sidebar entry.
- **New command:** add a case to `AppCommand`. The menu bar and the command palette pick it up from there.
- **Shared UI:** `Shared/Components/`. Theme tokens live in `Shared/Theme/` (`ColorToken`/`Theme` colour roles in light and dark, `Radius`, `Space`, `Metrics`, `Motion`, `TextRole`) and follow Luuna's desktop design system; never write a literal colour, size or duration in a view. Build screens from `Shared/Components/` (Page, PageHeader, Panel, RecordList, StatGrid, Facts, Callout, ReasonNote, EmptyState, StatusBadge with a `Tone`, button styles).
- **Pure logic** (parsing, date math, file rules): `DailyCore`, with tests in `DailyCoreTests`.
- **New setting:** a field in `WorkspaceSettings` (with a default in its decoder, so older `settings.json` files still load) and a property in `Preferences`. No `@AppStorage` or `UserDefaults` in views.
- **New app-owned file:** a URL on `WorkspaceDirectory` (`~/.config/daily-workspace/`). Never Application Support, never the vault, and never secrets: keys stay in the Keychain.
- **New disk, network or OS integration:** put a protocol at the boundary, a production implementation next to the feature, and a fake in `Tests/DailyWorkspaceTests/Fakes.swift`. Wire both in `AppModel.Dependencies`.
- **Diagnostics:** use the `Log` channels. Never log note text, chat content or keys. Log paths with `privacy: .private`, and log errors as `Log.code(error)` (public) plus the description with `.private(mask: .hash)`.

## Swift conventions

The code follows the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and
[Swift concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/). The
rules below are the ones review keeps coming back to.

**Naming and files**
- Name things for what they are at the point of use: types and protocols are nouns (`NoteVault`, `AgentTransport`),
  capability protocols end in `-ing`/`-able` (`TaskPersisting`, `LuunaRuntimeReading`), methods with side effects are
  verbs (`save(_:to:expecting:)`), and Boolean properties read as assertions (`isActive`, `isEmpty`).
- One primary type per file, named after the file. Split a large type into `Type+Topic.swift` extensions
  (`AssistantSession+Loop.swift`), each about one concern.
- Never give two types the same name in different modules: `DailyCore.JSONValue` (lossless decoded JSON) and the app's
  `OrderedJSON` (byte-stable request bodies) were split for this reason.
- Default to `private`; widen access only when another file needs it. `DailyCore` marks its API `public`; the app
  target stays `internal`.

**Concurrency** (complete checking is on for every target in `Package.swift`)
- Stores and anything that touches AppKit or SwiftUI state are `@MainActor`. Blocking work (file scans, `Process`,
  Keychain, Apple Events) leaves the main actor with `Task.detached` or a `nonisolated` async function, and returns
  `Sendable` values.
- Values that cross actors are `Sendable` structs or enums. `@unchecked Sendable` is allowed only for a small final
  class whose mutable state is guarded by a lock (`NSLock.withLock`) or another documented ordering, with a comment
  saying which.
- A main-actor class's `deinit` is nonisolated, so the handles it releases (timers, observer tokens, event monitors)
  are `nonisolated(unsafe) private var`: they are written only on the main actor and read once in `deinit`, after
  the last reference is gone. Use it for nothing else.
- A main-actor closure handed to an API whose callback is `@Sendable` but runs on the main thread (`Timer`,
  `addObserver(queue: .main)`) is bound with `nonisolated(unsafe) let` and called inside `MainActor.assumeIsolated`,
  with a comment naming the run loop or queue. Pass only `Sendable` values into that block.
- Frameworks that predate Sendable annotations (EventKit) are imported with `@preconcurrency` and used from the
  main actor only.
- Prefer `async`/`await` and `Task` over `DispatchQueue`. Use `DispatchQueue.main.async` only to defer to the next
  run-loop turn (for example a SwiftUI focus change in `onAppear`); inside `NotificationCenter` observers registered
  on `.main`, use `MainActor.assumeIsolated`.
- A task the UI started is cancelled when its owner goes away or the input changes, and a late result is discarded
  by checking an identity or generation, never applied over newer state.

**Errors and state**
- Throw typed errors with user-actionable descriptions; never put note text, server bodies or keys in an error.
- Model each source's state as an enum (`SourceState`) rather than a pile of optionals and flags, so "unavailable"
  can never render as "empty".
- No `try!`, force unwraps or `fatalError` on input from disk, the network or the user. A literal that cannot fail
  (a constant regex or URL) may force, with a comment.

## Tests

- Every change to core logic or a store comes with a test that would catch a regression users could notice.
- Store tests use the fakes and `AppModel.Dependencies.test(_:)`. File-safety tests use real temporary directories.
- EventKit, the Keychain, the global hotkey, IME and caret rendering are checked by hand. Follow [docs/TESTING.md](docs/TESTING.md) and say in the PR which checks you ran.

## Vault safety invariants

Any change that touches notes must keep all of these true:

1. A note is saved as exactly the loaded bytes plus the user's edits. No normalization, smart quotes or line-ending changes.
2. Saves are atomic, and they refuse to overwrite a file that changed on disk since it was loaded (`NoteVault.save(_:to:expecting:)`).
3. Never delete, rename or move vault files. Refuse files that are not UTF-8.
4. Nothing resolves outside the vault, symlinks included (`NoteVault.resolve`).
5. A discarded conflict version goes to the recovery folder first; if that fails, discard nothing.
6. Anything that reports success to the user (capture, task add) has already reached disk.

## Commits and pull requests

- Keep commits small and focused. Write the subject in the imperative ("Fix …", "Add …").
- Update `CHANGELOG.md` under **Unreleased** for any change a user could notice.
- Update `README.md` and `docs/ARCHITECTURE.md` when behaviour or structure changes.
- CI must pass: lint (swift-format, SwiftLint) → build → test → bundle → `Info.plist` usage-string check.
