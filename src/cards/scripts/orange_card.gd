# src/cards/scripts/orange_card.gd
class_name OrangeCard
extends CardScript

func on_cast(card: CardInstance, ctx: EffectContext) -> void:
	var hand := ctx.hand(ctx.me())
	if hand.is_empty():
		return
	ctx.request_choice(card, ChoiceSpec.select_cards(hand.duplicate(), 0, 1, "Reduce a card's fee by 1"), "orange_fee")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "orange_fee" and not result["cards"].is_empty():
		ctx.add_fee_modifier(result["cards"][0], -1)
