class_name BjornHammer
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var victims: Array = []
	for pidx in [ctx.me(), ctx.opponent()]:
		for u in ctx.board(pidx):
			if u.card_script == null or not u.card_script.has_request():
				victims.append(u)
	for v in victims:
		ctx.kill(v)
	ctx.end_turn()
