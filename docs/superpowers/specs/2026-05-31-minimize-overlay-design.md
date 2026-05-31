# Minimize Overlay Design

## Overview

Add a "minimize" button to all choice overlays in battle (CardSelectPanel, HandChoice, OptionPrompt, TrapRevealOverlay, LeaderCostPrompt, MulliganPanel). When clicked, the overlay's content shrinks into a small tab at the bottom of the screen, revealing the hand and board (non-interactive). Clicking the tab's expand button bursts the overlay back open. Inspired by Slay the Spire's reward/event screen minimize.

## Approach: MinimizeBar + Signal Coordination

A single `MinimizeBar` CanvasLayer in Match coordinates with each overlay via signals. Each overlay adds a minimize button and emits `minimize_requested`. Match manages the animation state.

## Components

### MinimizeBar (`src/ui/overlays/minimize_bar.tscn`)

```
MinimizeBar (CanvasLayer) [visible = false]
  InputBlocker (ColorRect) — full-screen, Color(0,0,0,0.15), mouse-eating
  Tab (HBoxContainer) — anchored bottom-center, pill style
    Title (Label) — e.g. "Select 2 cards to discard"
    ExpandButton (Button) — expand icon/chevron-up
```

- `show(title: String)` — sets title text, fade-in with `TRANS_ELASTIC` scale pop on tab.
- `hide()` — fade-out/shrink tab, then `visible = false`.
- Signal: `expand_pressed` — emitted when ExpandButton clicked.
- InputBlocker: 15% dim (vs overlay's 55%), eats all mouse events so board is visible but non-interactive.

### Per-Overlay Changes

Each of the 6 choice overlays gets:

1. A minimize button in its layout (near title/confirm area), with `JuicyButton` applied.
2. A new signal: `minimize_requested`.
3. A method: `get_animatable_nodes() -> Array[Node]` returning content nodes that shrink/expand.

Animatable nodes per overlay:

| Overlay | Animatable nodes |
|---|---|
| CardSelectPanel | Label (title), CardRow, Buttons |
| HandChoice | Title, Confirm button |
| OptionPrompt | Label (title), Options buttons, CardSlot (if present) |
| TrapRevealOverlay | TrapName, Body (card + context), Buttons |
| LeaderCostPrompt | PromptLabel, PayTickets, PayDiscard |
| MulliganPanel | Label, CardRow, ConfirmButton |

### Match.gd Coordination

New state:
- `_minimized_overlay: CanvasLayer` — which overlay is minimized (null when none)
- `_active_overlay: CanvasLayer` — which overlay is shown (null when none)

New connections in `_ready`:
- Each overlay's `minimize_requested` → `_on_overlay_minimize(overlay)`
- `MinimizeBar.expand_pressed` → `_on_overlay_expand()`

New methods:
- `_on_overlay_minimize(overlay)` — saves overlay ref, plays minimize animation, shows MinimizeBar with overlay title.
- `_on_overlay_expand()` — plays expand animation on minimized overlay, hides MinimizeBar, clears state.
- `_play_minimize_animation(overlay)` — for each node in `overlay.get_animatable_nodes()`: tween position toward MinimizeBar tab's global position while tweening scale to (0,0) with staggered delays. Parallel dim lerp from current to transparent. On completion: hide animatable nodes, reset transforms.
- `_play_expand_animation(overlay)` — for each node in `overlay.get_animatable_nodes()`: start at scale (0,0) at tab position, tween to saved rest position/scale with `TRANS_BACK` overshoot and `TRANS_ELASTIC` settle, staggered. Parallel dim lerp back. On completion: set final transforms.

## Animation Style

All animations follow the game's established juicy, bouncy, cartoony feel:

- **Shrink (minimize):** Items slurp toward the tab with `TRANS_BACK` ease-in (overshoot toward), scale shrinks to 0. Staggered timing — outer elements start slightly after inner ones for a cascading effect.
- **Expand (maximize):** Items burst from the tab position outward with `TRANS_BACK` overshoot (slightly past target) then settle with `TRANS_ELASTIC`. Staggered timing — inner elements appear first.
- **Dim transitions:** Lerp in-place (not moving). 55%→0% on minimize, 0%→55% on expand, using `TRANS_CUBIC`.
- **Tab appearance/disappearance:** `TRANS_ELASTIC` scale pop on the MinimizeBar tab.

Easing patterns match existing card_juice.gd and JuicyButton patterns.

## Edge Cases

### HandChoice Special Handling

HandChoice operates on actual hand cards in-place. When minimized:
- Staged (selected) cards stay in their staged positions — they do NOT shrink into the tab.
- Only the Title and Confirm button shrink.
- Hand cards remain visible but locked (`select_only` stays true). InputBlocker prevents clicking.
- On expand: Title and Confirm burst back. Staged cards were never moved.

### EndTurnButton

Already disabled/hidden when overlays are active. No changes needed — stays disabled while minimized.

### Animation Interruption

MinimizeBar's expand button is only visible after the minimize animation completes, so interruption during minimize is not possible. If expand is triggered during an ongoing expand animation (unlikely), existing tweens are killed and expand replays from current state toward the known rest transforms.

### Multiple Pending Choices

Not possible — the game only has one `pending_choice` at a time. No overlay stacking concern.

## File Changes Summary

| File | Change |
|---|---|
| `src/ui/overlays/minimize_bar.tscn` | New scene |
| `src/ui/overlays/minimize_bar.gd` | New script |
| `src/ui/match/match.tscn` | Add MinimizeBar child node |
| `src/ui/match/match.gd` | Add minimize/expand coordination logic |
| `src/ui/overlays/card_select_panel.tscn` | Add minimize button |
| `src/ui/overlays/card_select_panel.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/match/hand_choice.tscn` | Add minimize button |
| `src/ui/match/hand_choice.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/option_prompt.tscn` | Add minimize button |
| `src/ui/overlays/option_prompt.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/trap_reveal_overlay.tscn` | Add minimize button |
| `src/ui/overlays/trap_reveal_overlay.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/leader_cost_prompt.tscn` | Add minimize button |
| `src/ui/overlays/leader_cost_prompt.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |
| `src/ui/overlays/mulligan_panel.tscn` | Add minimize button |
| `src/ui/overlays/mulligan_panel.gd` | Add signal, `get_animatable_nodes()`, minimize button wiring |