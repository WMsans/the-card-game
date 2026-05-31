class_name TrebleClef
extends ClefCard

func reacts_to() -> Array: return [Enums.EventType.TURN_STARTED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	var c: int = int(card.vars.get("treble_turns", 0)) + 1
	card.vars["treble_turns"] = c
	if c % 2 == 0:
		ctx.harmonize()
