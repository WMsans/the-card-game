class_name Rat
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.CARD_RUMMAGED]
func active_zones() -> Array: return [Enums.Zone.HAND]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("instance", -1) != card.instance_id:
		return
	if not ctx.hand(ctx.me()).has(card):
		return
	ctx.summon_free(card)
