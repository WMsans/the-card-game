class_name RaccoonLeader
extends CardScript

func returns_on_reshuffle() -> bool: return true

func reacts_to() -> Array: return [Enums.EventType.TURN_STARTED]
func active_zones() -> Array: return [Enums.Zone.DISCARD]

func react(_card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	ctx.rummage(2)

func activated_abilities(card: CardInstance, ctx: EffectContext) -> Array:
	if card.zone != Enums.Zone.BOARD:
		return []
	if card.vars.get("opt_used_this_turn", false):
		return []
	if ctx.hand(ctx.me()).is_empty():
		return []
	return [{"id": "raccoon_throw", "label": "Discard cards to deal damage"}]

func activate(card: CardInstance, ability_id: String, ctx: EffectContext) -> void:
	if ability_id != "raccoon_throw":
		return
	card.vars["opt_used_this_turn"] = true
	var hand := ctx.hand(ctx.me())
	ctx.request_choice(card,
		ChoiceSpec.select_cards(hand.duplicate(), 0, hand.size(), "Discard any number of cards"),
		"rac_discard")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "rac_discard":
		var chosen: Array = result["cards"]
		for c in chosen:
			ctx.discard_from_hand(c)
		if chosen.is_empty():
			return
		card.vars["rac_amount"] = chosen.size()
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal %d damage to a Unit" % chosen.size()),
			"rac_target")
	elif tag == "rac_target" and not result["targets"].is_empty():
		ctx.deal_damage(result["targets"][0], int(card.vars.get("rac_amount", 0)))
