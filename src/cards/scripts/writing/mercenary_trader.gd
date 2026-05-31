class_name MercenaryTrader
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_TRASHED]
func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.DISCARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("instance", -1) == card.instance_id:
		ctx.gain_orange(ctx.me())
