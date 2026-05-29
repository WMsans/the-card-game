# VGDC: The Card Game — Rules/Combat Engine (Slice 1) Design

**Date:** 2026-05-29
**Status:** Approved (design); pending implementation plan
**Engine target:** Godot 4.6.3 (fresh project in this repo)
**Test framework:** GdUnit4

## Context

This is the first slice of a larger project to build "VGDC: The Card Game" (see
`docs/design_docs/`) in Godot, with Balatro-style card visuals and a
Slay-the-Spire-style layout. The full game decomposes into ~7 subsystems:
card data, card rendering, board/UI layout, rules engine, combat, card
abilities, and opponent. Each gets its own spec → plan → build cycle.

**This slice builds only the headless rules/combat engine** with placeholder
(no) visuals. It establishes the data model, turn/ticket/draw/reshuffle loop,
combat, and the event/trigger bus that card abilities will later hook into —
but implements only stat-only ("vanilla") cards. The rendering, layout,
ability, and opponent slices come later and build on this foundation.

### Design decisions already made (from brainstorming)

- **First slice:** rules/combat engine first (headless), before rendering.
- **Ability scope:** build the event/trigger framework, but only vanilla
  (stat-only) cards now. No per-card ability scripting in this slice.
- **Architecture:** action-driven engine over pure data (Option A).
- **Tests:** GdUnit4.

## Goals

- A fully headless, deterministic, test-driven engine that can play a complete
  two-player game of vanilla cards from setup to a deck-out win.
- A clean action/controller boundary so tests (now) and AI/UI (later) drive the
  engine through the same interface.
- An event/trigger bus and reaction-window mechanism in place so the future
  abilities slice can attach card effects without rewriting the engine.

## Non-goals (explicitly deferred to later slices)

- Any rendering, scenes, or `Node`-based UI.
- Real card abilities / keyword effects (REQUEST, RUMMAGE, TRASH, ORANGE,
  HARMONIZE, CLEF, real Trap conditions). Parsed and stored, but inert.
- AI opponent or networked/hotseat input handling beyond the action interface.
- Parsing/using the `Image` column or card art.

## Architecture: action-driven pure-data engine

Game state is plain data — `RefCounted` classes with **no `Node`/`SceneTree`
dependency** — so it instantiates trivially in headless tests. The engine
advances only through discrete **Actions**. It exposes the legal actions for the
current state; a "controller" submits one. Tests are controllers now; AI and UI
become controllers later through the same two methods:

- `get_legal_actions(state) -> Array[Action]`
- `apply(action) -> void` (mutates `GameState`, publishes events)

RNG is seeded and injected, so all shuffles/draws are deterministic and
replayable.

## 1. Domain model

### `CardDefinition` (static, parsed from CSV)
- `id: int`
- `deck_color: String` — Strike / Raccoon / Writing / Audio (from filename)
- `type: String` — Minion / Spell / Trap / Leader
- `name: String`
- `ticket_cost: int`
- `alt_discard_cost: int` — leaders only (e.g. `Discard 4` → 4); else 0
- `base_damage: int`
- `base_health: int`
- `ability_text: String` — stored, inert this slice
- `flavor: String` — stored, inert this slice
- `keywords: Array[String]` — stored, inert this slice

### `CardInstance` (runtime)
- `instance_id: int` — unique per game
- `definition: CardDefinition`
- `zone: enum` — DECK / HAND / BOARD / DISCARD / TRAP_SET / LEADER_SLOT
- `tapped: bool`
- `current_damage: int`, `current_health: int` — combat-mutated; reset to base
  on end-of-turn full-heal

### `PlayerState`
- `deck: Array[CardInstance]` (ordered; index 0 = top)
- `hand: Array[CardInstance]`
- `board: Array[CardInstance]` (units in play)
- `discard: Array[CardInstance]`
- `set_traps: Array[CardInstance]` (face-down traps)
- `leader: CardInstance` (starts in hand)
- `tickets_total: int`, `tickets_tapped: int`
- `reshuffles_remaining: int` — starts at 4
- `turn_counters: Dictionary` — cards_played, cards_discarded, attacks_made,
  units_died, etc. (bookkeeping future keywords will read; tracked now)

### `GameState`
- `players: [PlayerState, PlayerState]`
- `active_player: int`
- `turn_number: int`
- `phase: enum` — SETUP / START / MAIN / END / GAME_OVER
- `rng: SeededRng`
- `pending_choice: PendingChoice` (or null)
- `event_log: Array[GameEvent]`
- `winner: int` (or -1)

## 2. CSV ingestion (`CardDatabase`)

Parses the four deck CSVs into `CardDefinition`s. Must handle the real-data
quirks present in the source files:

- **Header variance:** first column is `a` in Strike, `Card ID` elsewhere —
  match by position/known headers, not exact name.
- **Cost strings:** `"7 / Discard 4"` → `ticket_cost=7`, `alt_discard_cost=4`;
  plain `"1"` → `ticket_cost=1`, `alt_discard_cost=0`.
- **Stat strings:** `"1 (3)"` → base `1` (parenthetical is the harmonized
  value, ignored this slice); blank/empty → `0`.
- **Image column:** ignored entirely this slice.
- **Deck color:** derived from filename (`Strike Deck v2.csv` → Strike, etc.).
- **Duplicates:** the 2-dupe rows are distinct rows and become distinct
  `CardInstance`s at deck-build time.

**Each CSV is already a complete deck:** row 1 = Leader, rows 2–21 = the 20-card
deck. The four files become four ready-made deck fixtures for tests. The CSVs
are copied into `res://game/data/decks/` so runtime does not depend on the
`docs/` directory layout.

Known source-data anomalies (tolerate, do not crash): a duplicated `id 17` in
the Writing deck, occasional blank/garbled `Image` cells, and stray whitespace.

## 3. Turn flow & tickets

### Setup
1. Each player draws their Leader into hand.
2. Each player draws the top 5 of their deck.
3. Each player discards 2 of those 5 (via `PendingChoice` → `ResolveChoice`),
   leaving a 3-card hand + Leader.
4. Seeded coin flip selects the first player.

### Ticket ramp (matches GDD numbers exactly)
- P1, turn 1: `tickets_total = 1`.
- P2, turn 1: `tickets_total = 2`.
- Every later own-turn START: untap all (`tickets_tapped = 0`), then
  `tickets_total = min(10, tickets_total + 2)`.
- Resulting progression — P1: 1, 3, 5, 7, 9, 10, … / P2: 2, 4, 6, 8, 10, 10, …
- Playing a card requires `tickets_total - tickets_tapped >= cost`; on play,
  `tickets_tapped += cost`.

### Turn phases
- **START:** untap all units and tickets; apply ticket ramp; draw 1 (including
  the first turn); reset `turn_counters`; publish `TURN_STARTED`.
- **MAIN:** play cards and declare attacks in any legal order.
- **END:** if `hand.size() > 5`, player discards down to 5 (via `PendingChoice`);
  full-heal all units to base stats; publish `TURN_ENDED`; pass to opponent.

### Playing cards
- **Minion:** pay cost; enters `board` **tapped** (per rules); publish
  `CARD_PLAYED`.
- **Spell:** pay cost; resolve effect (inert this slice); goes to `discard`.
- **Trap:** pay cost; placed in `set_traps` face-down (hidden).
- **Leader:** played from hand; cost paid by tickets **or** by discarding
  `alt_discard_cost` cards from the top of the deck; enters `board` as a unit.

## 4. Combat

- **`DeclareAttack`**: an **untapped** Minion or Leader attacks; the attacker
  taps. Target is an **enemy unit** or the **enemy Deck**.
- **Unit vs unit (simultaneous strike):** each unit deals its `current_damage`
  to the other's `current_health` at the same time.
  - **Lethal = incoming damage ≥ current health.** (Per the GDD worked example:
    a 3-damage attacker kills a 3-health leader. This overrides the looser
    "greater than" phrasing in *Cards & Play*.)
  - Dead units → `discard`; publish `UNIT_DIED`.
- **Unit vs deck:** opponent discards `attacker.current_damage` cards from the
  top of their deck (mill). **No retaliation.** Publish `DECK_DAMAGED`. This is
  the win path.
- **End of turn:** all damaged survivors heal to base stats.

## 5. Reshuffle & win condition

- `reshuffles_remaining` starts at **4**.
- Whenever a card is needed from an **empty** deck (a draw, or unresolved
  deck-damage): if `reshuffles_remaining == 0` → that player **loses**
  (`winner` = opponent, `phase = GAME_OVER`); otherwise shuffle the discard pile
  into the deck (seeded) and `reshuffles_remaining -= 1`, then continue.
- Deck damage of N is applied card-by-card; each time the deck empties mid-mill
  and more must be removed, a reshuffle is triggered by the same rule. So the
  5th needed reshuffle ends the game — the primary loss condition.

## 6. Event/trigger bus

- **`GameEvent`**: a `type` enum + payload dict. Types include `CARD_PLAYED`,
  `UNIT_ATTACKED`, `UNIT_DAMAGED`, `UNIT_DIED`, `DECK_DAMAGED`, `CARD_DISCARDED`,
  `TURN_STARTED`, `TURN_ENDED` (extensible).
- The engine publishes events at fixed points. Combat and `turn_counters` route
  through the bus now. Appended to `event_log` for test assertions.
- **Reaction windows + traps:** when an event opens a window (e.g. an attack
  declared during the opponent's turn), the engine checks `set_traps`; if a
  trap's condition matched, it pauses the current action, resolves the trap,
  discards it, and resumes. **This slice ships the plumbing only** — vanilla
  trap conditions never match, so nothing fires. The future abilities slice
  registers real triggers against this same bus with no engine rewrite.
- **`PendingChoice`:** anything requiring a follow-up decision (mulligan
  discards, attack-target selection, "activate trap?") sets `pending_choice`;
  the controller answers via a `ResolveChoice` action. This keeps the engine
  synchronous and fully testable — no `await`, no signals.

## 7. Actions & control interface

Action types: `Mulligan`, `PlayCard`, `DeclareAttack`, `EndTurn`,
`ActivateTrap`, `ResolveChoice`.

Engine exposes:
- `get_legal_actions(state) -> Array[Action]` — only currently-legal actions,
  honoring tickets, tap state, phase, and any open `pending_choice`.
- `apply(action) -> void` — validates, mutates state, publishes events.

## 8. Project structure

```
the-card-game/
  project.godot
  addons/gdUnit4/                  # test plugin
  game/
    data/
      card_definition.gd
      card_database.gd
      decks/                       # the four CSVs, copied in
    engine/
      game_state.gd
      player_state.gd
      game_engine.gd               # action processing, turn flow, legality
      combat.gd
      rng.gd                       # seeded, injectable
      actions/                     # one script per action type
      events/                      # event bus + event type defs
  tests/                           # GdUnit4 suites
  docs/superpowers/specs/          # this document
```

## 9. Testing plan (GdUnit4, test-first)

Each suite is written before its implementation:

1. **CSV ingestion** — cost/stat parsing quirks, header variance, four decks
   build to 20 cards + leader, anomalies tolerated.
2. **Ticket ramp** — P1/P2 starting amounts and +2 cap-10 progression; untap on
   turn start; cost payment and insufficient-ticket rejection.
3. **Draw / discard / hand-limit** — draw on turn start, end-of-turn discard to 5.
4. **Reshuffle & loss** — empty-deck reshuffle decrements; 5th needed reshuffle
   sets the winner and `GAME_OVER`.
5. **Play cards** — minion enters tapped & pays cost; spell → discard; trap →
   set; leader via tickets and via discard-cost.
6. **Combat** — simultaneous strike; lethal ≥ health (the 3-vs-3 example);
   deck-mill with no retaliation; unit-vs-unit retaliation; end-of-turn heal.
7. **Event bus & reaction plumbing** — events published at the right points and
   logged; reaction window opens and finds no matching vanilla trap.
8. **Legal-action generation** — correct action set across phases and with an
   open `pending_choice`.
9. **Determinism** — same seed ⇒ identical shuffles/draws/outcomes.
10. **Full scripted vanilla game** — drives the engine end-to-end via the action
    interface to a deck-out win.

## Confirmed rulings (resolved from ambiguous/contradictory docs)

1. **Lethal is ≥ health** (not strictly `>`), per the GDD worked example.
2. **Empty-deck draw/deck-damage consumes a reshuffle**; 0 reshuffles = loss.
3. **First-turn tickets:** P1 = 1, P2 = 2, then +2/turn capped at 10.
4. **Vanilla traps ship reaction plumbing only**; conditions do not fire yet.
