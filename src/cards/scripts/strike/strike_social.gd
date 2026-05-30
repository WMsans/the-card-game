class_name StrikeSocial
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) == ctx.me():
		return
	ctx.fire_trap(card)
	for u in ctx.board(ctx.me()):
		if u.card_script != null and u.card_script.has_request() and ctx.request_met(u):
			ctx.set_unit_flag(u, "immortal_this_turn")
