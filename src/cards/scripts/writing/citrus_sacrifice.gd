class_name CitrusSacrifice
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	var n := ctx.discard_pile(ctx.me()).size()
	for i in range(n):
		ctx.gain_orange(ctx.me())
