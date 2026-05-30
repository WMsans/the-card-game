# Juicy UI Refactor — Design

**Date:** 2026-05-30
**Status:** Approved design, ready for planning
**Scope:** Whole-game UI (main menu, in-match HUD, all overlays)

## Goal

The current UI is functional but flat: bare default Godot buttons, no shared
theme, muddy full-card tints for playability, no visual feedback on discard
selection, an asymmetric and unframed table layout, and no live feedback while
dragging a card. This refactor makes the UI **juicy, consistent, reusable, and
good-looking** under one cartoony art direction, and reworks the in-match layout
so it reads as deliberate.

This work is **purely additive in `src/ui/`**. No engine, data, or game-logic
files change.

## Art direction

**Playful / cartoony:** rounded chunky buttons, warm saturated colors, bouncy
motion, soft drop shadows. Matches the whimsical deck themes (raccoon, audio,
strike, writing).

## Architecture & file layout

A new shared theming backbone under `src/ui/theme/`:

```
src/ui/theme/
  ui_palette.gd        # static class: canonical colors + sizing constants
  game_theme.tres      # Godot Theme: Button/Panel/Label StyleBoxes, fonts, colors
  juicy_button.gd      # class_name JuicyButton extends Button
  card_highlight.gd    # class_name CardHighlight extends Control (glow-border overlay)
  drop_zone_overlay.gd # class_name DropZoneOverlay (dashed cartoony drop zones)
  fonts/               # cartoony display TTF referenced by the theme
```

Wiring:

- **Theme application via inheritance.** Set `theme = game_theme.tres` on the
  root `Control` of `main_menu.tscn` and `match.tscn`. Godot propagates the
  theme down the entire subtree, so every `Button`, `Panel`, and `Label` —
  including those inside overlays — picks up the styling with no per-widget work.
- **`UiPalette` is the single source of truth for color.** `game_theme.tres`
  references these colors for static chrome; `card_highlight.gd`,
  `drop_zone_overlay.gd`, and `ticket_tray.gd` read the same constants for
  dynamic visuals. One change propagates everywhere.
- **`JuicyButton`** replaces the bare `Button` type on interactive buttons. It
  inherits the theme look and *adds* motion. Static labels stay as `Label`.
- **`CardHighlight`** is a child overlay inside `card_view.tscn`, driven by a new
  `CardView.set_highlight(state)` method.
- **`DropZoneOverlay`** lives on a new `DropZoneLayer` node in `match.tscn`.

Follows the existing one-class-per-file, `class_name` conventions already used
across `src/ui/` (`CardView`, `BoardLayout`, `TicketTray`).

## Components

### `JuicyButton` (extends `Button`)

Keeps the theme's StyleBox look, adds tween motion. Pivot centered
(`pivot_offset = size / 2`) so scale/rotation grow from the middle. Tweens
kill-and-replace the previous one so rapid hover in/out never stacks.

- **Hover in:** scale → `1.08` + rotate to a fixed slight tilt (`±2.5°`, fixed
  per button so it reads as intentional, not jitter), `TRANS_BACK` / `EASE_OUT`,
  ~0.25s. Optional `modulate` brighten.
- **Hover out:** scale → `1.0`, rotation → `0`, `TRANS_ELASTIC`, ~0.4s settle.
- **Press down:** quick punch to scale `0.92` + slight counter-rotate, ~0.08s,
  `EASE_OUT`.
- **Release:** elastic pop back to hover-or-rest state.
- **Disabled:** tweens off, sits at rest, dimmed via the theme's disabled
  StyleBox (so End-Turn / Confirm visibly read as inactive).

Exported knobs: `hover_scale`, `tilt_deg`, `press_scale`, durations — tunable
per button without code changes, mirroring how `CardView` exposes tween params.

### `CardHighlight` (selection / resting glow only)

A `CardHighlight` overlay child inside `card_view.tscn`, sized to the card,
drawing a rounded **glow border** (a `StyleBoxFlat` with colored border + corner
radius, or a soft `_draw` glow). Hidden by default. Driven by
`CardView.set_highlight(state)` with an enum:

| State | Color (from `UiPalette`) | Used by |
|---|---|---|
| `NONE` | hidden | default |
| `PLAYABLE` | soft cyan, gentle pulse | resting hand cards playable this turn |
| `ATTACKABLE` | warm amber pulse | resting board units that can attack |
| `SELECTABLE` | soft cyan | discard / mulligan — cards you *may* pick |
| `SELECTED` | gold + small lift | discard / mulligan — cards you *have* picked |

This replaces the muddy flat `modulate` tints in `set_playable` /
`set_attackable` with a clean border glow, and reuses the **same component** for
discard/mulligan selection (which has no visual feedback today). Drag-state
feedback is **not** handled here — it lives on the board (see `DropZoneOverlay`).

### `DropZoneOverlay` — drag feedback on the board

A new `DropZoneLayer` node in `match.tscn` (alongside the existing
`DragLayer` / `FxLayer`). Drag feedback lives on the board, where the player's
eye already is during a drag, rather than glowing the card under the cursor.

Behavior while dragging a hand card:

- **Zone validity = placement legality (ignoring tickets).** If the dragged card
  is a playable *type* on your turn, its valid drop region(s) get a translucent
  shaded area: a **cartoony fill with a dashed/dotted outline**, palette-tinted
  neutral — advertising "droppable here." A minion shades the player board row; a
  spell/trap shades the play zone. A card that cannot be played at all right now
  (not your turn, wrong phase) shows **no** shading.
- **On hover, the shaded area recolors by affordability:** the zone under the
  cursor turns **green (acceptable)** or **amber (unaffordable — right place, too
  few tickets)**. Leaving the zone returns it to neutral.
- **Juicy interaction:** the zone under the cursor gives a little pulse / scale
  bump as the card enters it, so dropping feels responsive.

Driven by `match.gd` from its existing `_process` and `CardView` drag signals:
`drag_started` → compute and show valid zones; each frame → hit-test the cursor,
recolor the hovered zone by state; `drag_released` / drag end → clear.

The full drag picture in lockstep: shaded board zones appear, the one under the
cursor goes green, and the ticket pips that would be spent glow red. The card
itself stays clean.

### Ticket pips + cost preview

The pips get a cartoony pass: replace the plain `ColorRect` squares with rounded
pip "chips" (a small `StyleBoxFlat` panel, palette-colored). Same filled/empty
semantics as today.

- **Juicy spend/gain:** `TicketTray.set_tickets` diffs old vs. new count and
  animates only the delta — spending plays a staggered per-pip "drain" (pop +
  flip to empty); gaining pops pips in. Paying a cost feels tactile.
- **Red cost preview:** `TicketTray.preview_cost(n)` lights the `n` available
  pips that *would be spent* in red (glow); `clear_preview()` restores them.
  `match.gd` calls `preview_cost(card.ticket_cost)` exactly when the dragged card
  is over a valid zone and classifies as **acceptable**, and `clear_preview()`
  when the drag ends or stops being acceptable.

## Layout redesign (in-match)

Today's table is asymmetric and unframed: leader floats bottom-left,
deck/discard stack bottom-right, tickets and End-Turn dangle. The redesign makes
it **mirror-symmetric and grouped into framed "stations"** so it reads as
deliberate.

```
┌───────────────────────────────────────────────────────┐
│ [OPP LEADER]        opp hand (face down)   [DECK|DISC] │  top stations
│ ┌───────────────────────────────────────────────────┐ │
│ │              opponent board row                    │ │
│ │ ·············· felt table frame ·················· │ │  central
│ │              your board row                        │ │  play field
│ └───────────────────────────────────────────────────┘ │
│ [LEADER]                                   [DECK|DISC] │  bottom stations
│ [pips ▮▮▮▯▯]        your hand (fanned)     [End Turn]  │
└───────────────────────────────────────────────────────┘
```

- **Central play field:** a framed `Panel` (themed felt / rounded StyleBox)
  behind the two board rows, centered and inset from the edges, giving the board
  a clear playing surface instead of floating on a blank screen.
- **Four corner stations**, each a small framed `Panel`: player leader
  (bottom-left) with the ticket tray tucked beneath it; player deck + discard
  side-by-side (bottom-right) with the **End-Turn `JuicyButton`** anchored just
  inside it; opponent mirrors both at the top. Symmetric: leader-left /
  deck-discard-right for both players.
- **Hands** stay fanned across the bottom/top center, above their stations,
  unchanged mechanically but sitting on the new framed backdrop.
- Implementation: update the position constants in `board_layout.gd` and the
  node offsets in `match.tscn`, and add the `Panel` frames (pure visual,
  `mouse_filter = IGNORE` so they never eat input). Exact pixel values tuned
  during implementation against the 1920×1080 canvas.

## Theme rollout across screens

Mostly free via theme inheritance, plus targeted swaps:

- Set `theme = game_theme.tres` on the roots of `main_menu.tscn` and
  `match.tscn`.
- Swap `Button` → `JuicyButton` on interactive buttons: menu (deck buttons,
  Play, Quit), End-Turn, discard Confirm, mulligan Confirm, leader-cost
  Pay-Tickets / Pay-Discard, game-over Play-Again / Quit.
- **Overlay panels** (mulligan, discard, leader-cost, game-over, turn banner)
  get the cartoony rounded panel StyleBox + consistent padding and a title label,
  so popups feel like one family.
- **Main menu deck-selection fix:** selection currently has zero visual feedback
  for which deck is chosen. The chosen deck `JuicyButton` gets a persistent
  "selected" state (pressed-look + glow).
- **Font:** add a freely-licensed rounded TTF under `src/ui/theme/fonts/`,
  referenced by the theme. If a specific font is provided later, repoint the
  theme at it.

## Testing

This is a GdUnit4 project. Tweens and visuals are not unit-testable, so the
strategy is to **pull decision logic out of the visual nodes into pure
functions** and test those headless:

- **Drag classification** (`acceptable` / `unaffordable` / `invalid`) — a pure
  helper taking game state + card instance, tested across cases: not your turn,
  affordable, too few tickets, board full, wrong phase.
- **Drop-zone validity per card type** (which zones a minion vs. spell/trap
  advertises).
- **Ticket cost → pip mapping** (`preview_cost`).
- **`CardHighlight` state selection** (given hand/board context → which state).

All existing tests stay green; new pure helpers get fresh suites. The juice
itself (button tweens, dashed drop zones, pip animations, glow borders) is
verified manually by running a match.

## Out of scope

- Numeric ticket counter (pips are kept as-is; the cartoony pip pass and red cost
  preview are the only pip changes).
- Turn / round number readout.
- Any engine, data, or rules changes.
- New card art or frame assets (existing assets reused).

## New / changed files

**New:**
- `src/ui/theme/ui_palette.gd`
- `src/ui/theme/game_theme.tres`
- `src/ui/theme/juicy_button.gd`
- `src/ui/theme/card_highlight.gd`
- `src/ui/theme/drop_zone_overlay.gd`
- `src/ui/theme/fonts/` (display TTF)
- Pure drag-classification helper (e.g. extend `card_input.gd` or a new
  `drag_classifier.gd`) + its test suite.

**Changed:**
- `src/ui/card/card_view.tscn` / `card_view.gd` — add `CardHighlight` child +
  `set_highlight`; remove flat `modulate` playability tints.
- `src/ui/match/match.tscn` / `match.gd` — apply theme, add `DropZoneLayer`,
  drive drop-zone + pip-preview during drag, station/frame layout.
- `src/ui/table/board_layout.gd` — revised position constants.
- `src/ui/table/ticket_tray.gd` / `ticket_tray.tscn` — chip pips, spend/gain
  animation, `preview_cost` / `clear_preview`.
- `src/ui/menu/main_menu.tscn` / `main_menu.gd` — theme, `JuicyButton`, selected
  deck state.
- Overlay scenes (`discard_panel`, `mulligan_panel`, `leader_cost_prompt`,
  `game_over_panel`, `turn_banner`) — theme, `JuicyButton`, selection highlight
  via `CardHighlight`.
