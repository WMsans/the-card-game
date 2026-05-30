class_name CactusGuy
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.me())["attacks_made"] >= 2 \
		or ctx.counters(ctx.opponent())["attacks_made"] >= 2

func reacts_to() -> Array: return [Enums.EventType.DECK_DAMAGED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if not card.tapped:
		return
	if int(event.data.get("player", -1)) != ctx.opponent():
		return
	if card.vars.get("cactus_done_this_turn", false):
		return
	if ctx.discard_pile(ctx.opponent()).is_empty():
		return
	card.vars["cactus_done_this_turn"] = true
	ctx.steal_top_discard(ctx.opponent())
