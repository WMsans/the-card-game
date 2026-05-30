class_name RedAlien
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.me())["cards_discarded"] >= 2 \
		or ctx.counters(ctx.opponent())["cards_discarded"] >= 2

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if int(event.data.get("attacker", -1)) != card.instance_id:
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	card.vars["opt_used_this_turn"] = true
	ctx.request_choice(card,
		ChoiceSpec.choose_option(["Discard 1 from hand", "Mill 2 from Deck"], "Red Alien strikes!"),
		"red", ctx.opponent())

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag != "red":
		return
	var opp := ctx.opponent()
	if result["option"] == 0 and not ctx.hand(opp).is_empty():
		ctx.discard_from_hand(ctx.hand(opp)[0])
	else:
		ctx.mill(opp, 2)
