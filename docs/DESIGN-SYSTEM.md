# Design system

Daily Workspace has two visual systems, each in one place:

- **The main window** follows Luuna's desktop design system (`docs/DESIGN-SYSTEM.md` in the Luuna repository):
  Mantine's default-theme colours in light and dark, the system font for text and Outfit for headings, six tones
  that pair a colour with a shape, hover by background only. Its tokens live in `Shared/Theme`, its components in
  `Shared/Components` and `Shared/Shell`.
- **The Quick Panel** is a Turbo Pascal-style IDE over the desktop (owner decision, 2026-11-26: keep the Pascal
  panel style). Its palette, type and pane chrome live in `Features/QuickPanel/QuickPanelPascalTheme.swift`.

A view never draws with literals. `DesignSystemTests.testMainWindowViewsUseTokensNotLiterals` fails on
`Color(red:)`, numeric `.font(.system(size:))`, numeric `RoundedRectangle(cornerRadius:)`, system text styles
(`.font(.body)`) and `.foregroundStyle(.secondary)` anywhere outside the theme files and the Quick Panel.

## Tokens (`Shared/Theme`)

| Token | What it holds |
| --- | --- |
| `ColorToken` / `Theme` | Every colour role with its light and dark hex. Read colours as `Theme.ink`, `Theme.surface`, `Theme.accent`. Read status colours through `Tone`, so each state keeps its shape mark. |
| `TextRole` | Type roles: `pageTitle`, `sectionTitle`, `metric`, `wordmark`, `bodyStrong`, `body`, `bodySmall`, `label`, `caption`, `overline`, `mono`, `monoCaption`. Apply with `.textRole(_:)`, or `.font(TextRole.x.font)` where the line box would get in the way. |
| `IconRole` | SF Symbol sizes matched to adjacent text: `disclosure` 10, `caption` 11, `inline` 13, `control` 15, `leading` 16, `emptyState` 28 light. Apply with `.iconRole(_:)`. |
| `Space`, `Radius`, `Metrics` | The 4 pt rhythm, Mantine radii, control heights (28/32/40), page padding, sheet widths (480/640/720). |
| `Motion` | `stateChange` and `entrance`, both instant under Reduce Motion. |
| `Surfaces.swift` | The one rounded surface: `.surface(fill, edge:, radius:)`, plus `.mutedSurface()`, `.fieldSurface(focused:enabled:)`, `.cardSurface()`, `.softControlSurface()`, `.viewEntrance()` and `WorkspaceCanvas`. |

Colour rules worth repeating: the accent means Brody acts (primary action, the next step, focus, selection);
runtime activity is `info`; green only for verified or authorised states, never for "done"; text in the accent on
a selected ground uses `accentText`, which keeps 4.5:1 in dark mode where `accent` does not.

## Components

| Need | Use | File |
| --- | --- | --- |
| A screen | `Page { PageHeader(…); … }` | `PageHeader.swift` |
| A section | `Panel(title, description:, variant: .card / .subpanel / .plain)`, `SectionHeading`, `Tray` | `Panel.swift` |
| A list of records | `RecordList(variant: .rows / .cards) { RecordRow(title:meta:action:leading:trailing:) }` | `Records.swift` |
| Numbers and facts | `StatGrid`, `StatTile`, `Facts`, `FactRow` | `Stats.swift` |
| Status | `StatusBadge(text, tone:)`, `ToneMark`, `Tag`, `Kbd`, `ShortId` | `StatusBadge.swift`, `Tone.swift`, `ShortId.swift` |
| Feedback | `Callout(tone:)`, `ReasonNote(_, tone:, next:)`, `NextStepNote`, `EmptyState`, `StreamingDots` | `Feedback.swift` |
| Buttons | `.buttonStyle(.primary / .secondary / .quiet / .danger / .text)`, `.workspace(_, size:)`; `RowIconButton` for icon-only; `SegmentedControl`; `.toggleStyle(.quiet)` | `Buttons.swift`, `IconButton.swift`, `Fields.swift` |
| Text input | `BoxedTextField`, `SearchField`, `TextArea`, `.fieldChrome(focused:)` for a custom `TextField`; wrap in `LabeledField(label, hint:)` | `BoxedTextField.swift`, `Fields.swift`, `TextArea.swift`, `FormFields.swift` |
| Read-only text as stored | `CodePreview(text:)` | `TextArea.swift` |
| A sheet | `FormSheet(title, description:, width: .form / .review / .comparison) { …; FormFooter { Cancel; Primary } }` | `FormSheet.swift` |
| Wrapping chips | `ChipFlow` | `ChipFlow.swift` |
| Permissions and the vault | `PermissionPrompt`, `PermissionEmptyState`, `VaultStatusView`, `SettingsRow` | |
| Window chrome | `NavItem`, `TopBar`, `PaletteTrigger`, `StatusLine` | `Shell/ShellParts.swift` |

When a view needs a piece that two features would share, add it here rather than in a feature folder.

## Quick Panel (`QuickPanelPascalTheme.swift`)

| Piece | What it is |
| --- | --- |
| `PascalInk` | The panel palette: grounds (`overlay`, `band`, `pane`, `header`, `titleBox`, `selection`, `scrim`), rules (`activeRule`, `idleRule`), text (`primary`, `footer`, `meta`, `title`, `inactiveTitle`) and signals (`cyan`, `gold`, `coral`, `notice`). `QuickPanelPascalSkin.Ink` is an alias. |
| `PascalType` | The VGA face (or the configured font) with a monospaced fallback; `.panelFont(size)` reads it from the environment. |
| `PascalMetrics` | Band, row and header heights, pane insets, the title's lift into the rule. |
| `PascalPane(title, active:)` | One IDE window: double rule, boxed title, accessible heading. |
| `.pascalSelection(selected, focused:)` | The selected-row band, dimmed when its pane is not focused. |

## Review notes (2026-11-26)

An Apple HIG pass over the main window (`accessibility.md`, `color.md`, `typography.md`, `layout.md`,
`designing-for-macos.md`, `sheets.md`, `sf-symbols.md`) found the system already strong: computed AA contrast for
every text role, shape plus colour for every state, Reduce Motion honoured, visible focus rings, 28 pt minimum
controls. Fixed in this pass:

- Settings tabs drew the selected title in `accent` on `accentSoft`: 2.69:1 in dark mode, below 4.5:1. Now
  `accentText`, 5.45:1 (`color.md` › Best practices: sufficient contrast in both appearances).
- Four sheets each drew their own title, width and footer; two used `.roundedBorder` fields, `.font(.body)` and
  Cancel on the left. All now use `FormSheet`, `LabeledField`, `TextArea` and `FormFooter` (Cancel, then the one
  primary action on the right, with Return and Escape bound).
- Fields, cards and selected rows drew more than twenty hand-rolled `RoundedRectangle` pairs, some without the
  continuous corner. All now go through `.surface(…)` so corners and edges match everywhere.
- Symbol sizes were literal (10, 11, 13, 15, 16, 28). Now `IconRole`, matched to the text beside them.
- Two unused views (`InfoBanner`, `TaskRow`) used system colours outside the palette and were removed.

Deliberately kept: Settings stays in the main window and Quick Panel keeps its Pascal look (owner decisions in
AGENTS.md); sentence-case button titles, which are the app's convention throughout.
