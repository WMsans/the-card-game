class_name TrashCannon
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.RUMMAGE_PERFORMED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(_card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	ctx.deal_deck_damage(ctx.opponent(), 2)
