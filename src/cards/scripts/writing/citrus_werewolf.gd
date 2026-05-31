class_name CitrusWerewolf
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("attacker", -1) != card.instance_id:
		return
	if event.data.get("target_unit", -1) != -1:
		return
	ctx.gain_orange(ctx.me())
