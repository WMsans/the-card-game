class_name Coyote
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(3)

func rummage_bonus(_card: CardInstance, _ctx) -> int:
	return 1
