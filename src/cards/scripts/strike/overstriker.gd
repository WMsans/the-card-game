class_name Overstriker
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.gs().active_player)["cards_played"] >= 2

func reacts_to() -> Array: return [Enums.EventType.CARD_PLAYED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.opponent():
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	var played := _find_played(ctx, event.data.get("instance", -1))
	if played == null or played.definition.ticket_cost < 7:
		return
	card.vars["opt_used_this_turn"] = true
	ctx.mill(ctx.opponent(), 1)

func _find_played(ctx: EffectContext, instance_id: int) -> CardInstance:
	for pidx in range(2):
		for zone in [ctx.gs().players[pidx].board, ctx.gs().players[pidx].discard]:
			for c in zone:
				if c.instance_id == instance_id:
					return c
	return null
