class_name StrikeRequestForm
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var found := ctx.search_deck(func(c: CardInstance):
		return c.card_script != null and c.card_script.has_request())
	if found != null:
		ctx.draw_specific(found)
