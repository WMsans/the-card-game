class_name AncientOnesProtection
extends CardScript

func active_zones() -> Array: return [Enums.Zone.TRAP_SET]

func can_intercept_kill(card: CardInstance, dying: CardInstance, reason: String, ctx: EffectContext) -> bool:
	if reason != "battle":
		return false
	var owner := ctx.engine._owner_of(dying)
	for u in ctx.gs().players[owner].board:
		if u != dying:
			return true
	return false

func kill_on_fire(card: CardInstance, dying: CardInstance, ctx: EffectContext) -> bool:
	var owner := ctx.engine._owner_of(dying)
	var others: Array = []
	for u in ctx.gs().players[owner].board:
		if u != dying:
			others.append(u)
	if others.is_empty():
		return false
	if dying.current_health <= 0:
		dying.current_health = 1
	card.vars["aop_owner"] = owner
	ctx.request_choice(card,
		ChoiceSpec.select_target(others, 1, 1, "TRASH another Unit in its place"),
		"aop", owner)
	return true

func resume(_card: CardInstance, tag: String, result: Dictionary, ctx: EffectContext) -> void:
	if tag == "aop" and not result["targets"].is_empty():
		ctx.trash(result["targets"][0])
