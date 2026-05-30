class_name GrayAlien
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.hand(ctx.me()).size() >= 3

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var h := ctx.hand(ctx.me())
	ctx.request_choice(card, ChoiceSpec.select_cards(h.duplicate(), 0, h.size(), "Discard any number"), "gray_discard")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "gray_discard":
		var chosen: Array = result["cards"]
		for c in chosen:
			ctx.discard_from_hand(c)
		ctx.draw(chosen.size() + 1)
