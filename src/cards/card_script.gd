class_name CardScript
extends RefCounted

# Battlecry / on-play. Called after the card reaches its zone.
func on_cast(_card: CardInstance, _ctx) -> void: pass

# Triggered abilities. Called per active card after each event.
func react(_card: CardInstance, _event: GameEvent, _ctx) -> void: pass

# Resume point after a requested choice is answered.
func resume(_card: CardInstance, _tag: String, _result: Dictionary, _ctx) -> void: pass

# REQUEST predicate. Pure, side-effect free.
func condition_met(_card: CardInstance, _ctx) -> bool: return false
func has_request() -> bool: return false

# Activated abilities contributed to legal actions.
# Returns Array of {"id": String, "label": String}.
func activated_abilities(_card: CardInstance, _ctx) -> Array: return []
func activate(_card: CardInstance, _ability_id: String, _ctx) -> void: pass

# Cost system. Additive ticket delta (negative = cheaper). Pure.
func cost_modifier(_card: CardInstance, _ctx) -> int: return 0

# Classification predicates for "every Note" / "one CLEF" rules.
func is_clef() -> bool: return false
func is_note() -> bool: return false

# RUMMAGE: extra cards added per rummage instance while this card is on board.
func rummage_bonus(_card: CardInstance, _ctx) -> int: return 0

# Deck-damage interception (trap, in TRAP_SET).
func can_intercept_deck_damage(_card: CardInstance, _player: int, _amount: int, _ctx) -> bool: return false
# Called after the trap fires. Returns the remaining (un-negated) deck damage.
func deck_damage_on_fire(_card: CardInstance, _player: int, _amount: int, _ctx) -> int: return _amount

# Kill interception (trap, in TRAP_SET). reason is "battle" or "effect".
func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool: return false
# Called after the trap fires. Return true if it PREVENTED the death (engine must not kill).
func kill_on_fire(_card: CardInstance, _dying: CardInstance, _ctx) -> bool: return false

# TRASH replacements. Return a non-empty button label if this card offers a
# "may instead" replacement for trashing `target`; "" means not applicable.
func trash_replacement_for(_card: CardInstance, _target: CardInstance, _ctx) -> String: return ""
func apply_trash_replacement(_card: CardInstance, _target: CardInstance, _ctx) -> void: pass

# Dispatch hints.
func reacts_to() -> Array: return []                                  # event types
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.TRAP_SET]
