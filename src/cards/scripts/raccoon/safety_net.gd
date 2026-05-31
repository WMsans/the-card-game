class_name SafetyNet
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool:
	return true

func kill_on_fire(_card: CardInstance, dying: CardInstance, _ctx) -> bool:
	dying.vars["discard_to_bottom"] = true
	return false
