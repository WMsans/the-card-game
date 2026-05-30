class_name HeadphonesGhost
extends CardScript

func has_request() -> bool: return true
func condition_met(card: CardInstance, ctx: EffectContext) -> bool:
	return ctx.counters(ctx.me())["units_died"] >= 3 \
		or ctx.counters(ctx.opponent())["units_died"] >= 3

func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	var attacker_owner: int = event.data.get("player", -1)
	if attacker_owner < 0:
		return
	if ctx.counters(attacker_owner)["attacks_made"] != 2:
		return
	if card.vars.get("opt_used_this_turn", false):
		return
	var targets: Array = []
	for pidx in range(2):
		for u in ctx.board(pidx):
			if u.current_health <= 8:
				targets.append(u)
	if targets.is_empty():
		return
	card.vars["opt_used_this_turn"] = true
	ctx.request_choice(card, ChoiceSpec.select_target(targets, 1, 1, "Kill a Unit with 8 or less Health"), "ghost")

func resume(card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "ghost" and not result["targets"].is_empty():
		ctx.kill(result["targets"][0])
