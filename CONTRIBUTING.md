# Contributing

## Setup

The addon lives in `Needy/`. Link it into the client instead of copying (PowerShell; adjust `$wow`):

```powershell
$wow = "C:\Program Files (x86)\World of Warcraft\_forever_"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\Needy" -Target "$PWD\Needy"
```

`/reload` picks up changes, new files included.

## Layout

| Path | |
|---|---|
| `Needy/Core/` | Namespace, events and the internal message bus (`Init`), settings and saved variables (`Defaults`, `DB`), the loot API adapter (`LootSource`), runs (`Tracker`), the per-character wishlist (`Wishlist`), wishlists shared over addon messages (`Sharing`, protocol at the top of the file) and the awards and stats maths (`Titles`) |
| `Needy/UI/` | Widgets (`Widgets`), the themes for the bars and Roll Log (`Themes`), roll bars (`RollFrame`, with `WishlistGlow` for wanted items), the optional glow round new bars (`BarFlash`), the Wishlist tab's two lists, yours and everyone's (`WishlistPanel`), the Roll Log tab (`RollLog`), the History window and the Run Report (`SummaryWindow`, with `StatsPage` as its second tab) |
| `Needy/Integrations/` | Optional hooks into other addons (`DungeonJournal`) |
| `Needy/Config/` | The settings window, minimap icon and slash commands |
| `Needy/Test/` | Test mode: fake rolls and a fake party |
| `tools/` | The icon generator |
| `tests/` | Offline tests that run the addon against a mocked WoW API |

How it fits together:

- `LootSource` turns the game's events into Needy messages: `ROLL_START`, `ROLL_CLOSED`, `DROP_UPDATE` and so on (listed in `Core/Init.lua`). Test mode raises the same messages, so the UI and `Tracker` never care whether a roll is real.
- Live rolls come from `START_LOOT_ROLL`, `GetLootRollItemInfo` and `RollOnLoot`. Everyone's choices, rolls and the winner come from `C_LootHistory`.
- The DungeonJournal integration post-hooks two functions on that addon's table and reads its loot tables at runtime to say where items drop (all listed at the top of the file). It never edits that addon or copies its code or data. Needy must keep working without it, and if those functions change.
- A run starts when you enter a party or raid instance and ends when you leave. `/reload` inside resumes it. Leaving as a ghost (released after a wipe) doesn't end it: the run is kept "away" until you're back inside, enter another instance, or have been alive outside for 5 minutes (`Tracker` `keepAway`).
- Blizzard opens its popups from `GameEvent.HandleStartLootRoll`, not from a frame that can be unregistered. Needy makes `GroupLootFrame1-4` invisible and click-through instead of touching `GroupLootContainer`, which sits in the managed bottom-frame stack where taint could reach protected bars.
- WoW: Forever has need, greed and pass only. There are no transmog rolls, even though the client code supports them.

The source of truth for Blizzard's side is the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source).

## Tests

```powershell
python -m venv .venv
.venv\Scripts\pip install -r requirements-dev.txt
.venv\Scripts\python tests\check.py   # Lua 5.1 syntax, and backslash escapes Lua would drop
.venv\Scripts\python tests\smoke.py   # loads the addon against a mocked API and exercises it
```

CI runs both on every push and pull request, and builds the release zip without uploading it (see the run's artifacts).

## Generated files

- `Needy/Media/icon.tga` and `assets/logo.png`: the addon icon, from `tools\gen_icon.py` (source art `assets/rolling-dices.png`, CC BY 3.0, see README).
- `Needy/Media/mark.tga`: the wishlist heart, drawn by the same script in the icon's red and gold.

## Debugging

- `/needy debug` for Needy's own messages.
- `/console scriptErrors 1`, or BugSack, to see Lua errors.
- `/fstack` (frames under the cursor) and `/etrace` (events).
- `/console taintLog 1`, then read `_forever_\Logs\taint.log`, for "action blocked" problems.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta`. The TOC's `@project-version@` is replaced with the tag.

1. Update `CHANGELOG.md`.
2. Tag and push, e.g. `git tag v0.1.0-beta && git push origin v0.1.0-beta`. Tags containing `alpha` or `beta` are published as that release type.

Uploading needs the repository secrets `CF_API_KEY` (CurseForge) and `WAGO_API_TOKEN` (Wago), plus the project IDs as `## X-Curse-Project-ID` and `## X-Wago-ID` in `Needy/Needy.toc`. Without them, the release is only attached to GitHub.
