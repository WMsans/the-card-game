class_name SixteenthNote
extends CardScript

func is_note() -> bool: return true

func cost_modifier(_card: CardInstance, ctx) -> int:
	var notes := 0
	for u in ctx.board(ctx.me()):
		if u.card_script != null and u.card_script.is_note():
			notes += 1
	return -notes

func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, _event: GameEvent, ctx: EffectContext) -> void:
	if card.vars.get("harmonized", false):
		return
	card.vars["harmonized"] = true
	ctx.deal_deck_damage(ctx.opponent(), 4)
