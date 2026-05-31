class_name Staccato
extends CardScript

func on_cast(_card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
	ctx.gs().turn_flags["notes_double_damage"] = true
