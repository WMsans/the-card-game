extends GdUnitTestSuite

func test_flag_defaults_false_and_resets_each_turn() -> void:
	var ps := PlayerState.new()
	assert_bool(ps.all_requests_met_this_turn).is_false()
	ps.all_requests_met_this_turn = true
	ps.reset_turn_counters()
	assert_bool(ps.all_requests_met_this_turn).is_false()

class HasReq extends CardScript:
	func has_request() -> bool: return true
	func condition_met(card, ctx) -> bool:
		return ctx.counters(ctx.me())["cards_discarded"] >= 2

func test_request_met_uses_condition() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 800))
	u.card_script = HasReq.new()
	u.zone = Enums.Zone.BOARD
	state.players[0].board.append(u)
	state.active_player = 0
	assert_bool(eng._request_met(u)).is_false()
	state.players[0].turn_counters["cards_discarded"] = 2
	assert_bool(eng._request_met(u)).is_true()

func test_global_flag_forces_request_met() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 801))
	u.card_script = HasReq.new()
	u.zone = Enums.Zone.BOARD
	state.players[0].board.append(u)
	state.players[0].all_requests_met_this_turn = true
	assert_bool(eng._request_met(u)).is_true()

func test_immortal_unit_is_not_killed() -> void:
	var state := GameState.new(13)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 804))
	u.zone = Enums.Zone.BOARD
	u.vars["immortal_this_turn"] = true
	state.players[0].board.append(u)
	eng._kill(0, u)
	assert_array(state.players[0].board).contains([u])
