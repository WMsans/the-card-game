class_name CardScript
extends RefCounted

func on_cast(_card, _ctx) -> void: pass
func react(_card, _event, _ctx) -> void: pass
func resume(_card, _tag: String, _result: Dictionary, _ctx) -> void: pass
func condition_met(_card, _ctx) -> bool: return false
func has_request() -> bool: return false
func activated_abilities(_card, _ctx) -> Array: return []
func activate(_card, _ability_id: String, _ctx) -> void: pass
func reacts_to() -> Array: return []
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.TRAP_SET]
