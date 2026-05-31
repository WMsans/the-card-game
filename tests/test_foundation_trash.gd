# tests/test_foundation_trash.gd
extends CardTestBase

class ReturnToHandRep extends CardScript:
	func trash_replacement_for(card: CardInstance, target: CardInstance, _ctx) -> String:
		return "Return to hand" if card == target else ""
	func apply_trash_replacement(_card: CardInstance, target: CardInstance, ctx: EffectContext) -> void:
		var p: int = ctx.me()
		ctx.gs().players[p].board.erase(target)
		target.zone = Enums.Zone.HAND
		target.reset_stats()
		ctx.gs().players[p].hand.append(target)

class TrashCounter extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.UNIT_TRASHED]
	func active_zones() -> Array: return [Enums.Zone.BOARD, Enums.Zone.DISCARD]
	func react(card: CardInstance, event: GameEvent, _ctx) -> void:
		if event.data.get("instance", -1) == card.instance_id:
			card.vars["was_trashed"] = true

func test_trash_without_replacement_kos_unit_and_emits_event() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = TrashCounter.new()
	EffectContext.new(eng, me).trash(u)
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
	assert_bool(u.vars.get("was_trashed", false)).is_true()

func test_trash_with_replacement_prompts_and_returns_to_hand() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = ReturnToHandRep.new()
	EffectContext.new(eng, me).trash(u)
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	# option 0 = the replacement, last option = "Just KO it"
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(eng.state.players[me].hand.has(u)).is_true()
	assert_bool(eng.state.players[me].discard.has(u)).is_false()

func test_trash_choose_just_ko_when_replacement_available() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	u.card_script = ReturnToHandRep.new()
	EffectContext.new(eng, me).trash(u)
	eng.apply(Action.resolve_choice({"option": 1}))  # Just KO it
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
