class_name PainSplit
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var allies: Array = ctx.board(ctx.me())
	if allies.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(allies.duplicate(), 1, 1, "TRASH a Unit"), "ps_trash")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ps_trash":
		if result["targets"].is_empty():
			return
		card.vars["ps_trash_id"] = result["targets"][0].instance_id
		var units: Array = []
		for pidx in [ctx.me(), ctx.opponent()]:
			for u in ctx.board(pidx):
				units.append(u)
		if units.is_empty():
			_do_trash(card, ctx)
			return
		ctx.request_choice(card,
			ChoiceSpec.select_target(units, 1, 1, "Deal 4 damage to any Unit"), "ps_dmg")
	elif tag == "ps_dmg":
		if not result["targets"].is_empty():
			ctx.deal_damage(result["targets"][0], 4)
		_do_trash(card, ctx)

func _do_trash(card: CardInstance, ctx: EffectContext) -> void:
	var tid: int = int(card.vars.get("ps_trash_id", -1))
	var unit := ctx.engine._find_anywhere(tid)
	if unit != null:
		ctx.trash(unit)
