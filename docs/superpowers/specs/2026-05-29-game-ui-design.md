# Game UI — Design Spec

**Date:** 2026-05-29
**Status:** Approved for planning
**Scope:** Full playable vertical slice of the game UI, wired to the existing `GameEngine`.

## 1. Goal & Context

The game logic is complete and well-tested: `GameEngine`, `GameState`, `PlayerState`,
`EventBus`, deterministic `SeededRng`, combat, turn flow, mulligan, and
`get_legal_actions()`. **There is no UI or scene layer yet.** This spec covers
building the entire presentation + interaction layer so the game is playable
solo against a simple AI.

### Confirmed decisions

- **Scope:** Full playable vertical slice (card visuals + table + interaction +
  AI + flow), built in independent phases.
- **Opponent:** A built-in **AI bot** that chooses from
  `GameEngine.get_legal_actions()`. Solo play. Opponent hand shows as face-down
  backs; board / leader / discard are visible.
- **Interaction:** **Hybrid** — drag-and-drop to play cards from hand;
  click-source → click-target (with a drawn arrow) to declare attacks
  (Slay-the-Spire / Hearthstone convention).
- **Frames:** Text-free frame PNGs are provided at
  `docs/design_docs/Card List/Design & UI_UX MEGA COLLAB Cards/No text/`
  (`Minion Card-1.png`, `Leader Card.png`, `Spell Card.png`, `Trap Card.png`,
  plus `Card Back.png` from the parent folder). Dynamic text/numbers are
  overlaid onto blank regions. Frames are **750×1050 (5:7)**.
- **Gameplay depth:** **Vanilla only.** The UI displays ability/keyword/flavor
  text, but only the implemented vanilla rules resolve (cost/tickets, combat,
  draw, mill, reshuffle, hand limit, win/lose). Card abilities, keywords, and
  traps are visual-only for now (`_trap_condition_met` returns `false`, no
  ability resolution). Ability execution is a separate engine effort.
- **Feel:** Balatro-style tactile juice (hover tilt, dynamic shadow, drag
  wobble, dissolve on death), referenced from
  `/mnt/windows/Godot/godot_balatro_ui/scenes/balatro`.
- **Presentation target:** 1920×1080 landscape, `canvas_items` stretch.

## 2. Architecture

The UI is a **pure view over the authoritative `GameState`** (state-reconciliation
+ event flourishes). It **never mutates game state directly**; it only sends
`Action`s into `GameEngine` and reconciles its visual nodes from state afterward.
The engine remains untouched and deterministic except for one additive data
field (`CardDefinition.image`).

### Sync model (chosen: reconcile for layout + events for flourishes)

The source of truth is always `GameState`. After every applied action:

1. The UI **reconciles**: each `CardView` is told its correct home
   (zone + index → target transform) and tweens there. New cards spawn; cards
   that left animate out. This handles draw / play / move / death positioning
   automatically and can never drift from true state.
2. A small set of **events** captured from `EventBus` trigger one-shot
   cosmetic flourishes (damage numbers, dissolve, mill burst, shake, game over).

Rejected alternatives: pure event-driven (fragile — events are deltas, not
positions; easy to desync) and pure reconciliation (robust but misses "moment"
effects). The hybrid keeps robustness + testability while delivering juice.

### File structure

New code lives under `src/ui/`. Engine/data untouched except `CardDefinition.image`.

```
src/ui/
  match/
    match.tscn / match.gd        # root scene: owns engine+state, turn loop, AI, input routing
    ai_controller.gd             # picks from get_legal_actions() on AI turns
    board_layout.gd              # pure fn: zone+index -> target Transform (testable)
  card/
    card_view.tscn / card_view.gd   # renders a CardInstance onto a frame; hover/drag; signals
    card_art.gd                  # frame texture + art lookup per CardDefinition
  table/
    hand_view.gd                 # fans player's hand, hover-spread, drag pickup
    board_view.gd                # arranges a player's minions in a row
    pile_view.gd                 # deck / discard counts; leader slot
    ticket_tray.gd               # tickets total vs tapped
    opponent_hand.gd             # face-down backs (count only)
    targeting_arrow.gd           # bezier arrow attacker -> cursor/target
  overlays/
    mulligan_panel.gd
    discard_panel.gd
    leader_cost_prompt.gd
    turn_banner.gd
    game_over_panel.gd
  menu/
    main_menu.tscn / main_menu.gd
  assets/
    frames/   (blank Minion/Leader/Spell/Trap + Card Back PNGs)
    art/      (per-card art copied from docs images/)
```

**Boundaries:**
- `CardView` knows only how to render one card + emit input signals — no rules.
- `Match` is the only node that touches `GameEngine` / `Action`.
- `board_layout.gd` is pure data→transform math, unit-testable without a scene.

## 3. CardView (the foundation)

A single reusable `Control`-based scene that renders one card and emits input,
usable in hand fans, board rows, and overlay previews.

**Node tree:** root `Control` → `Frame` (`TextureRect`, per-type PNG) → overlay
children positioned by **ratio of 750×1050** (resolution-independent, re-tunable).

| Region | Node | Bound to | Shown when |
|---|---|---|---|
| Name box (top color bar) | `Label` (auto-shrink) | `definition.name` | always |
| ⭐ top-left | `Label` | `current_damage` (board) / `base_damage` (hand) | units only |
| ❤️ top-right | `Label` | `current_health` / `base_health` | units only |
| 🎟️ bottom-left | `Label` | `ticket_cost` | always |
| 🗑️ bottom-right | `Label` | `alt_discard_cost` | Leader only |
| Art box (upper) | `TextureRect` | art from `definition.image` | if art exists |
| Ability box (lower) | `RichTextLabel` | `ability_text` (keywords bolded) | always |
| Flavor box (gray) | `Label` (italic) | `flavor` | always |

The **type label** ("Minion"/"Spell"/…) is baked into the frame; not overlaid.

**API / behavior:**
- `setup(card_instance)` binds all fields and swaps the frame texture by
  `definition.type`. An overload/variant accepts a bare `CardDefinition` for
  previews.
- `set_face_down(bool)` shows the Card Back.
- Signals: `hovered`, `unhovered`, `drag_started`, `drag_released`, `clicked`.
- Stat labels show **current** values on board (combat damage visible) and
  **base** values in hand; tint red/green when buffed/damaged vs base.

**Card art lookup (`card_art.gd`):** add an `image` field to `CardDefinition`
parsed from CSV column 8 (`Image`); copy `docs/.../images/` art into
`src/ui/assets/art/`. Missing art → art box stays blank (graceful). Frame map:
MINION→Minion, SPELL→Spell, TRAP→Trap, LEADER→Leader, face-down→Card Back.

**Juice (encapsulated in CardView):** hover tilt toward cursor + scale-up +
raise, dynamic drop shadow, spring/oscillator wobble while dragging, dissolve
shader on death. Adapted from the reference `card.gd` to a `Control`.

Exact region rectangles are calibrated against the PNG in-editor during
implementation; this spec fixes them as approximate ratios.

## 4. Table layout & zone widgets

Two-sided board; opponent mirrored at top, player at bottom (1920×1080):

```
┌─────────────────────────────────────────────────────────┐
│ [opp leader] [opp deck][discard]   ‹opp hand: face-down backs›   │  top
│ ─────────────  OPPONENT BOARD ROW (minions)  ───────────── │
│                                                             │
│ ─────────────  PLAYER BOARD ROW (minions)   ───────────── │
│ [you leader] [your deck][discard]            [End Turn]     │
│ [ticket tray: ●●●○○ 3/5]      ‹your hand: fanned CardViews› │  bottom
└─────────────────────────────────────────────────────────┘
```

Widgets, each a small focused script over `CardView`s:
- **`hand_view`** — fans the player's `CardView`s along an arc; hover lifts /
  spreads neighbors; owns drag pickup.
- **`opponent_hand`** — N face-down backs (count only).
- **`board_view`** — centered row of a player's minions (one per player);
  highlights valid attackers (untapped) and valid targets during targeting.
- **`pile_view`** — deck and discard as stacked card-backs with a count badge;
  click discard → cosmetic peek overlay. Includes the **leader slot**.
- **`ticket_tray`** — draws `tickets_total` pips, `tickets_tapped` filled;
  affordability highlight derives from `available_tickets()`.
- **`targeting_arrow`** — bezier from attacker to cursor; snaps to a hovered
  enemy unit or the enemy deck pile.
- **Deck-as-target** — the opponent's deck pile is a clickable/droppable attack
  target (attacking the deck is legal) and pulses when an attacker is selected.

The `tapped` flag renders as a ~15° rotation on board cards. Affordability and
legal-target highlights are driven from `get_legal_actions()`, so the UI never
reimplements rules.

## 5. Match controller: turn loop, input, reconciliation

`match.gd` is the **only** node that touches `GameEngine` / `Action`.

**Setup:** load the four deck CSVs via `CardDatabase`, build two 20-card decks +
leaders (player's deck chosen from the menu; opponent assigned one),
`engine.setup(...)`, render initial state, raise the mulligan overlay.

**Core cycle (serialized so animations read clearly):**
1. An action is produced — by player input or the AI.
2. `engine.apply(action)` mutates `GameState` and publishes events to `EventBus`.
   (The published events for this action are captured.)
3. **Reconcile:** every `CardView` is sent to its correct home
   (`board_layout.gd` maps zone+index→transform) and tweens there. Entered cards
   spawn; cards moved to discard animate out; new hand cards fly from the deck.
4. **Flourishes** fire from the captured events:
   `UNIT_DAMAGED`→floating damage number + shake; `UNIT_DIED`→dissolve;
   `DECK_DAMAGED`→mill burst on the pile; `GAME_OVER`→game-over panel.
5. Refresh highlights from `get_legal_actions()`. If it's the AI's turn (or a
   `pending_choice` belongs to the AI), schedule the next AI step after a delay.

**Player input → Action mapping:**
- Drag a hand `CardView` onto a legal drop zone → `Action.play_card(instance_id)`.
  Leader dragged onto the deck/🗑️ region, or via the leader cost prompt when both
  payments are legal → `pay_by_discard`.
- Click an untapped board minion → **targeting**; click enemy unit →
  `declare_attack(attacker, {unit})`; click enemy deck →
  `declare_attack(attacker, {deck:true})`; click elsewhere / Esc cancels.
- **End Turn** button → `Action.end_turn()`.
- Only actions present in `get_legal_actions()` are accepted; illegal drops snap
  back.

**AI (`ai_controller.gd`):** on the AI's turn, repeatedly read
`get_legal_actions()` and pick one (configurable: random, or simple greedy —
play affordable cards, attack favorably, then end turn), applied through the same
cycle so it animates identically. AI `pending_choice` (mulligan / discard)
resolved by a simple heuristic.

**`pending_choice` handling:** `Match` watches `state.pending_choice` after every
cycle. `"mulligan"` → mulligan overlay (or AI heuristic); `"discard_to_limit"` →
discard overlay. Resolving sends `Action.mulligan(...)` /
`Action.resolve_choice(...)`.

## 6. Overlays & game flow

Lightweight `CanvasLayer` panels that pause table input while active:
- **Mulligan panel** — shows the opening hand; per the GDD the player discards
  **exactly 2** of the 5 drawn (Leader excluded from the discardable set);
  confirm → `Action.mulligan(indices)`. The engine discards those indices (no
  redraw), so the hand settles to its post-mulligan size. Sequence: player
  mulligan → AI mulligan → first player chosen → first turn.
- **Discard-to-limit panel** — on `pending_choice.kind == "discard_to_limit"`,
  player picks `count` cards → `Action.resolve_choice({indices})`.
- **Leader cost prompt** — when a Leader is playable by both tickets and discard,
  a two-button prompt picks `pay_by_discard`; skipped when only one is legal.
- **Turn banner** — brief "Your Turn / Opponent's Turn" sweep on `TURN_STARTED`.
- **Game-over panel** — on `GAME_OVER`, shows winner + "Play Again" (re-`setup`
  with a fresh seed) / "Quit".
- **Main menu** (`main_menu.tscn`) — Play vs AI → choose deck color, Quit. Sets
  the RNG seed (random, or fixed for testing) and loads `match.tscn`. This is the
  project's `run/main_scene`.

## 7. Testing strategy

UI tests focus on the seams, not pixels (engine is already covered):
- **Pure-logic unit tests (GdUnit4, no scene):** `board_layout.gd`
  (zone+index→transform), `card_art.gd` (definition→frame/art path + missing-art
  fallback), `ai_controller.gd` (always returns a legal action; terminates a
  turn), input→`Action` mapping (a drop/target resolves to the expected `Action`;
  illegal inputs rejected).
- **CardView data-binding (`GdUnitSceneRunner`):** `setup(instance)` populates
  name/damage/health/cost labels and selects the correct frame per type;
  face-down shows the back; current vs base stats render.
- **Reconciliation test:** after a scripted `play_card`, the matching `CardView`
  ends positioned in the board zone; after a kill it's removed. Driven through
  `Match` against a seeded engine.
- **CSV parse test:** the new `CardDefinition.image` field is populated.
- **Manual smoke:** a full vs-AI game runs start→win with no errors (deck-damage
  path reaches `GAME_OVER`).

## 8. Build phases

Each phase is independently runnable/reviewable.

1. **Data + assets:** add `image` field + CSV parse; import blank frames + Card
   Back + art into `src/ui/assets/`.
2. **`CardView`:** static render of any card onto frames + art (debug grid scene
   showing all cards). *Visible milestone.*
3. **Juice:** hover/drag/shadow/wobble/dissolve on `CardView`.
4. **Static table:** hand fan, board rows, piles, ticket tray, leader slots,
   opponent backs — rendered from a seeded `GameState` (no interaction).
5. **`Match` + reconciliation + flourishes:** wire the apply→reconcile→flourish
   cycle; turn banner.
6. **Player input:** drag-to-play, click-target attacks, end turn, leader prompt,
   affordability/target highlights from `get_legal_actions()`.
7. **Overlays:** mulligan, discard-to-limit, game-over.
8. **AI + flow + main menu:** AI controller, deck selection, play-again; full
   game loop.

## 9. Out of scope

- Card ability / keyword / trap execution (engine work).
- Networked / hotseat multiplayer.
- Deck building, collection, progression, audio.
- Final art for frames beyond the provided placeholders.
