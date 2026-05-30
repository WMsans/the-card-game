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

# Dispatch hints.
func reacts_to() -> Array: return []                                  # event types
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.TRAP_SET]
