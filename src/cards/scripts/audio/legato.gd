class_name Legato
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.harmonize()
	var tapped: Array = []
	for u in ctx.board(ctx.me()):
		if u.tapped:
			tapped.append(u)
	if tapped.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(tapped, 0, 1, "Untap one Tapped Unit"), "legato")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "legato" and not result["targets"].is_empty():
		ctx.untap(result["targets"][0])
