class_name Shelley
extends CardScript

func trash_replacement_for(card: CardInstance, _target: CardInstance, _ctx) -> String:
	if card.zone != Enums.Zone.BOARD:
		return ""
	return "Send to bottom of Deck"

func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
	ctx.to_deck_bottom(target)
