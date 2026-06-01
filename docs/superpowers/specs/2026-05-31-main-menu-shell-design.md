# Main Menu Shell — Design

**Date:** 2026-05-31
**Status:** Approved (pending implementation plan)

## Goal

Replace the bare-bones main menu (`src/ui/menu/main_menu.tscn`) with a Slay-the-Spire-style
menu hub: an atmospheric landing menu, a deck-select/Embark screen, a display-settings screen,
and a browsable compendium — all sharing one continuous animated background that also persists
into the match itself.

## Reference & Inspiration

Slay the Spire's main menu: a moody, persistent world; an asymmetric bottom-left logo + vertical
menu; a hub that flows into a character-select screen before "Embark". We adapt this to a
deck/leader picker for a 1v1 card game.

## Current State (what we're replacing)

- `src/ui/menu/main_menu.gd` / `.tscn`: title label, 4 deck buttons, a seed `LineEdit`, Play/Quit.
  Hardcoded offsets, no background. Opponent hardcoded to `raccoon`.
- `MainMenu._on_play()` instantiates `match.tscn`, adds it to the root, calls `start_game()`,
  and frees the menu.
- `match.tscn` owns its own `BalatroBg` child; `match.gd` connects `BalatroBg.foreground_offset`
  to `_on_foreground_offset` to parallax its foreground. "Play Again" restarts in place; game-over
  "Quit" exits the app.
- `project.godot` `run/main_scene` = `res://src/ui/menu/main_menu.tscn`.

## Architecture

A new persistent root scene, **`AppShell`** (`src/ui/shell/app_shell.tscn` + `app_shell.gd`),
becomes the project's `main_scene`. It owns the whole app for its lifetime.

```
AppShell (Control)
├── BalatroBg            # created once, never freed; continuous drift + parallax + shake
└── ContentLayer (Control)  # exactly one panel mounted at a time
        └── <active panel>
```

### Panels (each its own focused scene + script)

| Panel             | Scene                                  | Notes                                  |
|-------------------|----------------------------------------|----------------------------------------|
| `LandingPanel`    | `src/ui/shell/landing_panel.tscn`      | the menu (replaces `main_menu`)        |
| `DeckSelectPanel` | `src/ui/shell/deck_select_panel.tscn`  | the Embark screen                      |
| `SettingsPanel`   | `src/ui/shell/settings_panel.tscn`     | display options                        |
| Compendium        | `src/ui/card/card_gallery.tscn` (reuse)| mounted as a panel, unchanged          |
| Match             | `src/ui/match/match.tscn` (refactored) | gameplay panel                         |

### Shell responsibilities & API

The shell owns navigation, transitions, the single background, and match launch. Panels never
reference each other — they emit intent signals; the shell decides what to mount.

```
goto_landing()
goto_deck_select()
goto_settings()
goto_compendium()
start_match(seed: int, my_deck: String, opp_deck: String)
```

Panel → shell intents (signals): `play_pressed`, `compendium_pressed`, `settings_pressed`,
`quit_pressed`, `back_pressed`, `embark(seed, my_deck, opp_deck)`.

### Match refactor

- Remove the `BalatroBg` node from `match.tscn`.
- In `match.gd`, replace `@onready var _bg: BalatroBg = $BalatroBg` with an injected reference.
  The shell calls `match.attach_background(bg)` after mounting; Match then connects
  `bg.foreground_offset` to `_on_foreground_offset`.
- **Optional wiring:** if no background is injected (a test instantiating `match.tscn` directly,
  or running it standalone), Match skips foreground-parallax wiring and runs normally. This keeps
  the existing Match test suites green and Match independently runnable.

## Background: continuous parallax + parallaxed shake

`BalatroBg` is created once by the shell and is shared by every panel, including Match — so the
noise drift and mouse parallax never reset across screen transitions (the "never left the world"
feel), and the menu→match transition is seamless.

**Shake is folded into the existing parallax** rather than being a separate system:

- Add `add_trauma(amount: float)` to `balatro_bg.gd`. Trauma accumulates (clamped to a max) and
  decays each frame.
- The shake offset (trauma² × random direction, standard trauma-shake) is applied **additively**
  to the existing `_bg_current` (the node's `position`) and to `_fg_current` (the emitted
  `foreground_offset`), scaled by the same per-layer ratios as parallax (`bg_max_offset` vs
  `fg_max_offset`). The foreground therefore shakes harder than the background — the shake is
  **parallaxed**.
- Every foreground subscriber inherits the shake for free: the landing panel's drifting cards and
  Match's foreground both listen to `foreground_offset`.

## Screens

### Landing menu (layout A — Slay-the-Spire classic)

- Logo + vertical menu anchored **bottom-left**; the open right side hosts drifting cards.
- **Logo:** "THE CARD GAME" as a styled `Label` using the theme font and the cream/orange palette.
  Text for now; swappable for a logo texture later.
- **Menu rows** (top→bottom): **Play · Compendium · Settings · Quit**. Each is a `Button` with
  `JuicyButton.apply()` for the shared springy hover/press. Order top-to-bottom with Play first.
- **Credits:** a small link tucked in a corner; opens a lightweight credits panel (contributor
  list + Back). Minimal.
- **Drifting cards:** 4–5 card-back sprites (reusing the existing card-back art,
  `res://src/ui/assets/frames/back.png`) drifting/rotating slowly across the right two-thirds.
  They subscribe to the shell `BalatroBg`'s `foreground_offset` so they parallax (and shake) with
  the same channel Match uses. Decorative only: `MOUSE_FILTER_IGNORE`, count capped for perf.
- Emits: `play_pressed`, `compendium_pressed`, `settings_pressed`, `quit_pressed`,
  plus a credits intent.

### Deck-select / Embark (layout B — showcase + tray)

- **Showcase (left):** the currently-selected deck shown large — the deck **leader's image** via
  `CardArt.leader_art_path(deck_color)`, plus the leader's **name** and **flavor/ability text**
  pulled from the deck CSV (row 1 is the Leader). Fully data-driven; no authored copy.
- **Tray (right):** 4 deck tiles to switch *your* deck; the selected tile gets the accent glow
  (same idea as today's `_refresh_deck_selection`, `UiPalette.ACCENT`). Below it, an **Opponent**
  selector — a compact labeled control cycling through the 4 decks.
- **Bottom bar:** ◀ **Back** (→ landing), **Seed (optional)** `LineEdit` (blank = random; same
  parsing as today's `_seed_value()`), **Embark ▶** (→ `start_match`).
- **Deck pick = big parallaxed shake:** selecting a deck (yours or opponent's) calls
  `bg.add_trauma(BIG_AMOUNT)` through the shell.
- Carry over from `main_menu.gd`: `deck_path(color)` and seed parsing.
- Emits: `back_pressed`, `embark(seed, my_deck, opp_deck)`.

### Settings (display-only)

- `SettingsPanel`: **Fullscreen** toggle (`CheckButton` → `DisplayServer.window_set_mode`),
  **VSync** toggle (`DisplayServer.window_set_vsync_mode`), **◀ Back**.
- **Persistence:** settings save to `user://settings.cfg` via `ConfigFile`, loaded and applied
  once in `AppShell._ready()` so they persist across launches. Structure leaves room for audio
  settings later.

## Navigation, transitions & game-over flow

- The shell swaps panels with a **crossfade**: fade out the current panel → free it → mount and
  fade in the next, over the continuous background. A single reusable transition routine on the
  shell.
- **Play** → DeckSelect; **Embark** → crossfade into Match; **Back** buttons unwind toward Landing;
  **Compendium**/**Settings** mount their panels and Back returns to Landing.
- **Game-over** gains a return path: "Play Again" restarts in place (as today); **"Main Menu"**
  crossfades back to Landing (background stays continuous) instead of quitting. Quit-to-desktop
  remains available.

## Files

**New**
- `src/ui/shell/app_shell.gd` / `.tscn`
- `src/ui/shell/landing_panel.gd` / `.tscn`
- `src/ui/shell/deck_select_panel.gd` / `.tscn`
- `src/ui/shell/settings_panel.gd` / `.tscn`
- (optional) a small credits panel scene/script

**Modified**
- `src/ui/match/balatro_bg.gd` — add `add_trauma()` + parallaxed shake into `_process`.
- `src/ui/match/match.tscn` — remove the `BalatroBg` node.
- `src/ui/match/match.gd` — injected/optional background via `attach_background()`;
  add a "Main Menu" return on game-over.
- `project.godot` — `run/main_scene` → `res://src/ui/shell/app_shell.tscn`.

**Removed**
- `src/ui/menu/main_menu.gd` / `.tscn` (superseded by shell + landing panel).

## Testing (GdUnit4)

- Replace `tests/test_main_menu.gd` with:
  - `test_landing_panel` — buttons emit the correct intent signals.
  - `test_deck_select_panel` — deck/opponent selection state, `deck_path`, seed parsing,
    leader-art lookup, emits `embark` with the right args.
  - `test_settings_panel` — toggles call the right `DisplayServer` methods and write the config.
  - `test_app_shell` — navigation mounts the correct panel; `start_match` injects the background.
  - `test_balatro_bg_shake` — `add_trauma()` perturbs the emitted `foreground_offset` and decays
    back to zero over time.
- Existing Match suites stay green via the optional-background guard.

## Non-Goals / Out of Scope

- No save system → no **Continue**.
- No stats/persistence → no **Stats** screen.
- No audio in the project → **no audio settings** (display-only); the settings file is structured
  to add them later.
- No new card art or leader art beyond what already exists.
