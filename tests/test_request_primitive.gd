extends GdUnitTestSuite

class HasReq extends CardScript:
	func has_request() -> bool: return true
	func condition_met(card, ctx) -> bool:
		return ctx.counters(ctx.me())["cards_discarded"] >= 2

func test_flag_defaults_false_and_resets_each_turn() -> void:
	var ps := PlayerState.new()
	assert_bool(ps.all_requests_met_this_turn).is_false()
	ps.all_requests_met_this_turn = true
	ps.reset_turn_counters()
	assert_bool(ps.all_requests_met_this_turn).is_false()

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

func _ready_attack_engine() -> GameEngine:
	var state := GameState.new(11)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func test_request_attacker_gets_plus_two_and_survives() -> void:
	var eng := _ready_attack_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	# Attacker: 3 HP with a REQUEST that is met (global flag).
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 3, 802))
	atk.card_script = HasReq.new()
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	eng.state.players[me].board.append(atk)
	eng.state.players[me].all_requests_met_this_turn = true
	# Defender: deals 4 damage. Without the +2 HP buff the attacker (3 HP) dies.
	var def := eng.state.make_instance(TestFactory.minion(1, 4, 4, 803))
	def.zone = Enums.Zone.BOARD
	eng.state.players[opp].board.append(def)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	# Attacker survived (3+2-4 = 1 HP) and is still on the board.
	assert_array(eng.state.players[me].board).contains([atk])
	# A REQUEST_MET event fired.
	assert_int(eng.state.bus.events_of_type(Enums.EventType.REQUEST_MET).size()).is_equal(1)
