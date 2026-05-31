class_name TrashDay
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.request_choice(card,
		ChoiceSpec.choose_option(["0", "1", "2", "3"], "Discard how many from your Deck?"),
		"td_count")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "td_count":
		var n: int = result["option"]
		var actual: int = min(n, ctx.gs().players[ctx.me()].deck.size())
		if actual <= 0:
			return
		ctx.mill(ctx.me(), actual)
		card.vars["td_amount"] = actual
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal %d damage to a Unit" % actual),
			"td_dmg")
	elif tag == "td_dmg" and not result["targets"].is_empty():
		ctx.deal_damage(result["targets"][0], int(card.vars.get("td_amount", 0)))
