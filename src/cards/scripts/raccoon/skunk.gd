class_name Skunk
extends CardScript

func reacts_to() -> Array: return [Enums.EventType.RUMMAGE_PERFORMED]
func active_zones() -> Array: return [Enums.Zone.BOARD]

func react(card: CardInstance, event: GameEvent, ctx: EffectContext) -> void:
	if event.data.get("player", -1) != ctx.me():
		return
	if ctx.counters(ctx.me())["rummages_made"] != 1:
		return
	var targets: Array = ctx.board(ctx.opponent())
	if targets.is_empty():
		return
	ctx.request_choice(card,
		ChoiceSpec.select_target(targets.duplicate(), 0, 1, "Set an opponent Unit's Damage to 0"),
		"skunk")

func resume(_card: CardInstance, tag: String, result: Dictionary, _ctx: EffectContext) -> void:
	if tag == "skunk" and not result["targets"].is_empty():
		result["targets"][0].current_damage = 0
