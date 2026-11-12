# Contributing

## Prerequisites

- macOS 14+ with Xcode 15+ command line tools (Swift 5.9 or newer).
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
- **Shared UI:** `Shared/Components/`. Theme tokens go in `Shared/Theme/WorkspaceTheme`.
- **Pure logic** (parsing, date math, file rules): `DailyCore`, with tests in `DailyCoreTests`.
- **New setting:** a property and key in `Preferences`. No `@AppStorage` string literals in views.
- **New disk, network or OS integration:** put a protocol at the boundary, a production implementation next to the feature, and a fake in `Tests/DailyWorkspaceTests/Fakes.swift`. Wire both in `AppModel.Dependencies`.
- **Diagnostics:** use the `Log` channels. Never log note text, chat content or keys. Log paths with `privacy: .private`, and log errors as `Log.code(error)` (public) plus the description with `.private(mask: .hash)`.

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
