class_name HarmonizeSpell
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
