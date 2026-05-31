class_name BountyStriker
extends CardScript

func has_request() -> bool: return false

func reacts_to() -> Array: return [Enums.EventType.REQUEST_MET]
func active_zones() -> Array: return [Enums.Zone.DISCARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	if not ctx.discard_pile(ctx.me()).has(card):
		return
	ctx.gs().players[ctx.me()].discard.erase(card)
	card.zone = Enums.Zone.HAND
	ctx.gs().players[ctx.me()].hand.append(card)
