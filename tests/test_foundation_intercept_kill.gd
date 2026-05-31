extends CardTestBase

class SafetyNetStub extends CardScript:
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func can_intercept_kill(_card: CardInstance, _dying: CardInstance, _reason: String, _ctx) -> bool:
		return true
	func kill_on_fire(_card: CardInstance, dying: CardInstance, _ctx) -> bool:
		dying.vars["discard_to_bottom"] = true
		return false

func _set_trap(eng: GameEngine, p: int, script: CardScript) -> CardInstance:
	var t := eng.state.make_instance(TestFactory.trap(3, 20))
	t.card_script = script
	t.zone = Enums.Zone.TRAP_SET
	eng.state.players[p].set_traps.append(t)
	return t

func test_kill_without_interceptor_goes_to_discard_top() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_bool(eng.state.players[me].discard.has(u)).is_true()
	assert_object(eng.state.players[me].discard.back()).is_same(u)

func test_safety_net_redirects_kill_to_bottom_on_fire() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var filler := eng.state.make_instance(TestFactory.minion(1, 1, 1, 99))
	filler.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(filler)
	_set_trap(eng, me, SafetyNetStub.new())
	var u := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	eng._kill(me, u, "effect")
	assert_str(eng.state.pending_choice.kind).is_equal("intercept")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_object(eng.state.players[me].discard.front()).is_same(u)
