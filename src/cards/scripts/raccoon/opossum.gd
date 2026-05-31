class_name Opossum
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(3)
