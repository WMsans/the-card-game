class_name Trashalanche
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	var n := ctx.discard_pile(ctx.me()).size() - 1
	if n <= 0:
		return
	var victims: Array = []
	for pidx in [ctx.me(), ctx.opponent()]:
		for u in ctx.board(pidx):
			victims.append(u)
	for v in victims:
		ctx.deal_damage(v, n)
