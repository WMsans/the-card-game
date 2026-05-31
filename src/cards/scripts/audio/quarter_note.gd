class_name QuarterNote
extends CardScript

func is_note() -> bool: return true

func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	card.current_damage += 2
