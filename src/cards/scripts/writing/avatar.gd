class_name Avatar
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var others: Array = []
	for u in ctx.board(ctx.me()):
		if u != card:
			others.append(u)
	if others.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(others, 0, others.size(), "TRASH any number of your Units"),
		"avatar_self")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "avatar_self":
		var ids: Array = []
		for u in result["targets"]:
			ids.append(u.instance_id)
		card.vars["avatar_self_ids"] = ids
		var n := ids.size()
		var opp_units: Array = ctx.board(ctx.opponent())
		if n > 0 and not opp_units.is_empty():
			var k: int = min(n, opp_units.size())
			ctx.request_choice(card,
				ChoiceSpec.select_target(opp_units.duplicate(), k, k, "Opponent: TRASH %d of your Units" % k),
				"avatar_opp", ctx.opponent())
		else:
			_execute(card, ctx, [])
	elif tag == "avatar_opp":
		var opp_ids: Array = []
		for u in result["targets"]:
			opp_ids.append(u.instance_id)
		_execute(card, ctx, opp_ids)

func _execute(card: CardInstance, ctx: EffectContext, opp_ids: Array) -> void:
	for tid in card.vars.get("avatar_self_ids", []):
		var u := ctx.engine._find_anywhere(int(tid))
		if u != null:
			ctx.trash(u)
	for tid in opp_ids:
		var u2 := ctx.engine._find_anywhere(int(tid))
		if u2 != null:
			ctx.trash(u2)
