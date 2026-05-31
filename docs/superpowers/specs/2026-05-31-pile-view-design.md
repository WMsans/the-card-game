# Pile View — Design

**Status:** Approved design, ready for implementation planning.

## Goal

Let the player inspect the contents of any pile (deck or discard, for both
players) by clicking it, Slay-the-Spire style. Clicking a pile opens a modal
listing that pile's cards, **sorted by type then name**, with the cards flying
out of the pile and arcing into a scrolling grid. The pile stack widgets, now
interactive, also gain juicy hover feedback consistent with the rest of the
game.

Today the four pile widgets (`PlayerDeck`, `PlayerDiscard`, `OppDeck`,
`OppDiscard`) only show a card back and a count; their `clicked` signal exists
but is wired to nothing. This feature gives that signal a purpose.

## Scope

- A modal overlay (`PileOverlay`) showing one pile's cards in a scrolling grid.
- A pure sort helper (`PileSort`): type enum order, then case-insensitive
  alphabetical by full card name.
- A fly-out + flip animation from the clicked pile into the grid.
- Hover juice on the four pile stack widgets (`pile_view.gd`).

**Out of scope:** any engine/game-logic change. The overlay is handed a card
list; it never mutates game state. No fly-*back* animation on close.

## Key decisions (locked during brainstorming)

1. **All four piles are inspectable** — player deck/discard *and* opponent
   deck/discard. Opponent piles are shown fully revealed; this is a deliberate
   design choice for this game, not a leak.
2. **Scrolling grid layout**, reusing the `CardGallery` `ScrollContainer` +
   `GridContainer` style.
3. **Fly-out on open only**, with a face-down → face-up squash-flip mid-flight
   (the same mechanism the draw transition uses). Close is a quick dismiss, no
   fly-back.
4. **Sort order:** card type in `Enums.CardType` enum order
   (Minion → Spell → Trap → Leader), then case-insensitive alphabetical by full
   card name, letter by letter. Stable for equal keys.
5. **Architecture: new `PileOverlay` Control + pure `PileSort` helper.** Sort
   logic is pure and unit-tested (mirrors `TransitionPlan` / `StagedSelection`);
   the view is a dumb consumer. Not baked into `pile_view.gd` (a tiny reusable
   stack widget) and not a bent `CardGallery` (a standalone all-decks screen).

## Components & data flow

**`PileSort`** (`src/ui/table/pile_sort.gd`) — pure `RefCounted`, no scene deps:

- `static func sorted(cards: Array[CardInstance]) -> Array[CardInstance]` —
  returns a **new** array sorted by `(definition.type, definition.name.to_lower())`.
  Stable for equal keys. Does not mutate the input.

**`PileOverlay`** (`src/ui/table/pile_overlay.gd` + `.tscn`) — a `Control`
covering the table, hidden by default. Children:

- `Backdrop` — semi-transparent `ColorRect` dimming the table; `MOUSE_FILTER_STOP`
  so the table underneath isn't interactable while open; clicking it closes.
- `Title` — `Label` (e.g. "Your Deck", "Opponent's Discard").
- `CloseButton` — small ✕ button.
- `Scroll/Grid` — `ScrollContainer` + `GridContainer` (CardGallery layout)
  holding the spawned `CardView`s.

Public API:

- `open(cards: Array[CardInstance], from_pos: Vector2, title: String)` — sort via
  `PileSort`, build the grid, run the fly-out, show the backdrop.
- `close()` — quick fade/scale-down dismiss, then hide and free the spawned
  `CardView`s.

**Data flow** (the live scene is `match.gd` / `match.tscn`, not the standalone
`table_view` preview):

```
pile_view.clicked  ──►  match._on_pile_clicked(zone, player)
                          gathers that pile's Array[CardInstance] from state
                          + FlightAnchors.of(zone, player, self) (pile center)
                          + a title
                          ──► pile_overlay.open(cards, pos, title)
```

`match` already holds `state`, so it reads `you.deck`, `you.discard`,
`opp.deck`, `opp.discard` directly, and `FlightAnchors.of(zone, player, self)`
already returns each pile's screen center. The overlay never touches game state.

**Opponent-deck click is context-sensitive.** `_opp_deck.clicked` is already
wired to `handle_deck_target_clicked` (attack the deck when one of your units is
the selected attacker). That behavior is preserved: when an attacker is selected
*or* the player is choosing a target (`_selected_attacker != -1` or
`_targeting_for_choice`), the opponent-deck click stays an attack/target; only
otherwise does it open the contents overlay. The other three piles (player deck,
player discard, opponent discard) open the overlay unconditionally (subject to
the empty/already-open/`_anim_busy` guards).

## Fly-out animation

`GridContainer` slots aren't known until layout runs, so the sequence is:

1. `open()` sorts the cards and adds one `CardView` per card to `Grid` (giving
   them their final slot via container layout).
2. Wait one frame for the container to lay out, then read each card's resting
   slot (`global_position`) and call `set_rest(slot, 0.0)`.
3. For each card: place it at `from_pos` (the clicked pile's screen position),
   face-down, then `CardFlight.fly_in(cv, from_pos, delay)` with a per-card
   **stagger** (~`CardFlight.STAGGER`) so the burst reads as *dealt*.
4. At ~60% through each card's flight, a `tween_callback` triggers the existing
   squash-flip (`CardView.flip_to_face_up`).

The stagger follows the **same** sorted order, so the burst visually "writes
out" the sorted list.

Cards in the grid are **view-only**: `set_interactive(true)` so hover-zoom works
for inspection, but drag/select is off (nothing to play them onto).

## Close, edge cases, interactivity

- **Closing:** clicking `Backdrop`, the ✕ button, or `Escape` (`ui_cancel`).
  `close()` runs a quick (~0.15s) fade + slight scale-down, then hides and frees
  the spawned `CardView`s. No fly-back.
- **Empty pile:** clicking a pile with 0 cards does nothing (`table_view`
  returns early; the `pile_view` back is already hidden at count 0).
- **Re-click / double-open:** if the overlay is already open, ignore further
  pile clicks until it closes (guard flag).
- **Large piles** (full deck ~20–30 cards): `ScrollContainer` handles overflow;
  the effective stagger is clamped when the count is high so a big pile doesn't
  take too long to finish flying in (cap the total fly-in window).
- **Input gating:** the backdrop catches mouse input so the table underneath is
  inert while the overlay is open.

## Pile hover juice

The four pile widgets (`pile_view.gd`) are now interactive, so they get hover
feedback in the same elastic family as `CardView`:

- **`mouse_entered`** — quick elastic scale pop (~1.08×) plus a small lift,
  using `TRANS_ELASTIC` / `TRANS_BACK` easing to match `CardView`'s hover tweens.
- **`mouse_exited`** — elastic settle back to rest scale/position.
- Tweens are killed-and-replaced on rapid re-hover (same guard pattern as
  `CardView._tween_hover` / `_tween_unhover`) so flicking across piles doesn't
  ratchet.
- Only animates when the pile is non-empty (count > 0); an empty pile isn't
  clickable and shouldn't invite a hover.

## Testing strategy

Mirrors the existing "assert end-state, not mid-motion" philosophy.

- **`PileSort`** (`tests/test_pile_sort.gd`) — pure unit tests: mixed
  `CardInstance` arrays sort to enum-type then case-insensitive name; stable for
  equal keys; input array is not mutated; empty and single-card inputs.
- **`PileOverlay`** (`tests/test_pile_overlay.gd`) — scene tests:
  - `open()` spawns one `CardView` per card in `PileSort.sorted(...)` order
    (assert grid children's instances match).
  - After layout settles (await frames), each card's `_rest_position` equals its
    grid slot — asserting the flight *contract*, not the tween.
  - `close()` frees all spawned `CardView`s and hides the overlay.
  - Empty pile and already-open guard behave as specified.
- **`pile_view` hover** (`tests/test_pile_view.gd`) — hover sets the pile's scale
  above rest and exit returns it; gated on count > 0 (no hover animation at
  count 0).
- **`table_view` wiring** — invoking `_on_pile_clicked` opens the overlay with
  that pile's cards and title; opponent piles resolve to the right list.

## File structure

- **Create** `src/ui/table/pile_sort.gd` + `tests/test_pile_sort.gd`
- **Create** `src/ui/table/pile_overlay.gd` + `src/ui/table/pile_overlay.tscn`
  + `tests/test_pile_overlay.gd`
- **Create** `tests/test_pile_view.gd`
- **Modify** `src/ui/table/pile_view.gd` — hover juice (gated on count > 0);
  `clicked` carries no args, so `match` binds zone/player when connecting
- **Modify** `src/ui/match/match.gd` — `_on_pile_clicked(zone, player)`, gather
  pile lists + titles, open the overlay; make `handle_deck_target_clicked`
  context-sensitive (attack when targeting, else open overlay)
- **Modify** `src/ui/match/match.tscn` — add `PileOverlay` instance; connect the
  four piles' `clicked` signals (with bound zone/player)
- **Possibly modify** `src/ui/card/card_view.gd` — only if `flip_to_face_up`
  needs a mid-flight trigger hook it doesn't already expose (it returns a
  `Tween`, so likely usable as-is)

## Test command (headless, one suite)

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<suite>.gd
```

Exit code 0 = pass. Harmless headless noise to ignore: `ERROR: Required object
"rp_font" is null` and the "InputEvents not transported in headless" notice.
