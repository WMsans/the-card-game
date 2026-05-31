class_name TrashToTreasure
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	ctx.rummage(2)
	var hand := ctx.hand(ctx.me())
	if hand.is_empty():
		return
	var n: int = min(2, hand.size())
	ctx.request_choice(card,
		ChoiceSpec.select_cards(hand.duplicate(), n, n, "Put 2 cards on the bottom of your Deck"),
		"ttt")

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ttt":
		for c in result["cards"]:
			ctx.to_deck_bottom(c)
