# In-hand Card Selection ("fly to middle") — Design

**Date:** 2026-05-31
**Status:** Approved for planning
**Branch:** `feat/card-logic`

## Problem

The current card-choosing interface (`CardSelectPanel`) is a full-screen overlay
that shows *copies* of cards in a row and asks the player to click them. It is
confusing: it hides the board, the cards are detached from the hand they came
from, and it does not resemble the selection idiom players know from games like
Slay the Spire.

We want selections that draw from the player's **hand** to happen *in place*:
the player clicks cards directly in their hand, and each selected card flies to a
staged row in the middle of the screen. Selecting more cards than allowed
replaces the rightmost staged card. The player confirms from a floating control.

## Scope

- **In scope:** Selections whose source pool *is* the human player's hand.
  Today that is the `discard_to_limit` choice and any `card_effect` /
  `select_cards` whose card list consists entirely of cards currently in the
  human player's hand (raccoon leader discard, `trash_to_treasure`, gray alien,
  orange card, etc.).
- **Out of scope (unchanged):** Selections from non-hand pools — the existing
  `CardSelectPanel` overlay remains the path for these (cultist returning a card
  from the discard pile, `priority_raise` moving a REQUEST card from deck
  candidates). Opponent/AI choices are untouched. `choose_option`,
  `select_target`, `intercept`, and `mulligan` flows are untouched.

## Engine contract (unchanged)

Both affected choices resolve by **index** and must continue to:

- `discard_to_limit`: `Action.resolve_choice({"indices": [...]})`, where each
  index addresses `state.players[player].hand`
  (`game_engine.gd:_apply_resolve_choice`).
- `card_effect` / `select_cards`: `Action.resolve_choice({"indices": [...]})`,
  where each index addresses `spec.cards` (`game_engine.gd:_build_choice_result`).

The new UI changes only *how the player picks*; it still emits a list of indices
into the same source list. No engine changes are required.

## Architecture (Approach A)

A dedicated controller drives the **real** `CardView` nodes already living in
`hand_view`. No card copies are instantiated and no cards are reparented.

### Components

**`HandChoiceController`** — new, `src/ui/match/hand_choice.gd` with a thin scene
`src/ui/match/hand_choice.tscn`.
- The scene is a `CanvasLayer` (or `Control`) holding a centered title `Label`
  and a `Confirm` `Button`, positioned: title directly above the staged-card
  row, Confirm directly below it, both centered horizontally on screen.
- Public API:
  - `start(source_cards: Array, min_n: int, max_n: int, title: String) -> void`
  - signal `confirmed(indices: Array)`
- Owns at most one active session. Guards against a second `start()` before the
  current session confirms.
- Does **not** instantiate cards. It references `hand_view` to read the real
  `CardView` nodes (`hand_view.card_views`) and to drive layout.

**`hand_view`** — extended (`src/ui/table/hand_view.gd`):
- `set_choice_excluded(ids: Array) -> void` — re-lay-out the hand over the
  non-excluded cards only, so the hand reflows to close gaps left by staged
  cards. Excluded cards are *not* positioned by `hand_view` (the controller owns
  their position while staged). Passing `[]` restores the normal full layout.
- `set_drag_locked(locked: bool) -> void` — disable drag start and hover-lift
  while a selection is active; re-enable on confirm.
- Reuses existing `BoardLayout.slot(...)` math and the existing per-card tweens.
- `card_views` (id → `CardView`) is already public and is the controller's
  handle on the real cards.

**`match.gd`** — extended for routing only:
- Add `@onready var _hand_choice = $HandChoice` and connect
  `_hand_choice.confirmed` → `apply_action(Action.resolve_choice({"indices": idx}))`.
- In `_route_pending_choice` / `_route_card_effect`, decide hand-pool vs. overlay
  (see below) and dispatch accordingly.
- Add the `HandChoice` node instance to `match.tscn`.

**`CardSelectPanel`** — unchanged. Still the path for non-hand pools.

### Pool discrimination

A choice uses the in-hand flow iff its source list is entirely the human
player's current hand:

- `discard_to_limit` → always hand pool → `HandChoiceController`.
- `card_effect` with `ui_shape == "select_cards"` → hand pool iff **every**
  `spec.cards[i].instance_id` is present in `state.players[HUMAN].hand`.
  - If yes → `HandChoiceController`, started with `spec.cards` as the source list.
  - If no → existing `_select.show_selection(...)` overlay (unchanged).

The controller is always started with the *exact* list whose indices the engine
expects (`hand` for `discard_to_limit`, `spec.cards` for `card_effect`). On
confirm it maps each staged `instance_id` back to its index in that source list.

## Pure selection state (testable helper)

The selection bookkeeping is factored into a small, scene-free helper so it can
be unit-tested without instantiating nodes — e.g. an inner class
`StagedSelection` in `hand_choice.gd` (or a standalone
`src/ui/match/staged_selection.gd`).

State: `staged: Array` of `instance_id` in selection order; `min_n`, `max_n`;
the ordered `source_ids` (instance_ids of the source list, index-aligned).

Operations (pure, return enough info for the controller to animate):
- `toggle(id)`:
  - if `id` already staged → remove it (deselect).
  - else if `staged.size() < max_n` → append `id` (select).
  - else (`staged.size() == max_n`) → remove the **rightmost** staged id, then
    append `id` (replace-rightmost; new card lands in the vacated rightmost slot).
  - Returns a small struct describing what changed: `added`, `removed` (may be
    empty), so the controller knows which cards to fly to center and which to
    return to hand.
- `can_confirm() -> bool`: `min_n <= staged.size() <= max_n`.
- `to_indices() -> Array`: map each staged id to its index in `source_ids`,
  preserving staged order.

## Interaction & animation

All staged cards keep **the same size as they are in the hand**
(`BoardLayout.CARD_SCALE`) — no scale-up when flying to the middle.

1. **Activate** (`start`): lock hand drag/hover; show title (above center) and
   Confirm (below center). Confirm enabled iff `can_confirm()` — so for `min==0`
   it is enabled immediately. Only cards in the source list are clickable; if the
   source list is the whole hand (the common case) every hand card is clickable.
2. **Select (under max):** clicked card tweens from its hand slot to the next
   staged slot in a horizontal, centered row; `hand_view.set_choice_excluded`
   reflows the remaining hand to close the gap.
3. **Select at max:** the rightmost staged card flies back into the hand (hand
   reflows open); the newly clicked card flies into the now-vacated rightmost
   staged slot.
4. **Deselect:** clicking a staged (center) card flies it back into the hand;
   hand reflows; the staged row re-centers/compacts to fill its gap.
5. **Confirm:** emit `confirmed(to_indices())`; deactivate (clear chrome,
   `set_choice_excluded([])` is implicit because `match.gd` will
   `render_all()`); unlock drag. `match.gd` applies the resolve-choice action.

### Coordinate handling

Staged cards remain children of `hand_view` (a `Node2D`); they are **not**
reparented. The controller computes the centered staged-row slot positions and
converts the screen-center anchor into `hand_view`'s local space, then tweens the
real `CardView` nodes there. This avoids breaking `hand_view.card_views`, the
drag-signal wiring, or coordinate spaces.

### Staged row layout

- Horizontal row, centered on screen, using the same card scale as the hand.
- Slot spacing: reuse hand spacing conventions where practical; otherwise a fixed
  separation that keeps up to `max_n` cards comfortably centered. (Visual detail;
  default to values consistent with `BoardLayout`.)

## Edge cases

- **Variable count** (`min 0`, e.g. "discard any number"): Confirm always
  enabled; staged row may hold up to `max_n` (often the full hand). When
  `max_n == hand size`, replace-rightmost never triggers.
- **Empty source list** with `min == 0`: Confirm enabled immediately; nothing to
  stage.
- **AI / opponent choices:** only `pc.player == HUMAN` reaches this UI; the AI
  resolution path (`ai_controller.gd`) is untouched.
- **Re-entrancy:** controller permits one active session; ignores `start()` while
  active.
- **Non-hand pools:** routed to `CardSelectPanel` as today; behavior unchanged.

## Testing

- **Pure `StagedSelection` tests** (no scene):
  - `toggle` selects under max, deselects when re-toggled.
  - `toggle` at max removes rightmost and appends new (replace-rightmost),
    including the resulting order.
  - `can_confirm` boundaries for `min`/`max`, including `min == 0`.
  - `to_indices` maps staged order → correct indices into the source list,
    including after replace/reorder.
- **Pool-discrimination test:** a `select_cards` list drawn entirely from the
  human hand routes to the controller; a list containing any non-hand card routes
  to `CardSelectPanel`.
- **Regression:** existing choice/`CardSelectPanel` and engine resolution tests
  stay green — the engine still consumes `{"indices": [...]}` unchanged.

## Out of scope / future

- Applying the fly-to-middle idiom to non-hand pools (discard/deck candidates)
  would require rendering cards that are not physically in the hand; deferred.
- Keyboard/controller navigation of the selection.
