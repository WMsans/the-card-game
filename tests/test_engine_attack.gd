extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func _place(eng: GameEngine, owner: int, dmg: int, hp: int, id: int) -> CardInstance:
	var ci := eng.state.make_instance(TestFactory.minion(1, dmg, hp, id))
	ci.zone = Enums.Zone.BOARD
	ci.tapped = false
	eng.state.players[owner].board.append(ci)
	return ci

func test_attack_deck_mills_opponent_and_taps_attacker() -> void:
	var eng := _engine()
	var atk := _place(eng, eng.state.active_player, 3, 3, 400)
	var opp := eng.state.opponent()
	var deck_before := eng.state.players[opp].deck.size()
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_int(eng.state.players[opp].deck.size()).is_equal(deck_before - 3)
	assert_bool(atk.tapped).is_true()
	assert_int(eng.state.active().turn_counters["attacks_made"]).is_equal(1)

func test_unit_vs_unit_lethal_kills_defender() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var atk := _place(eng, me, 3, 4, 401)
	var def := _place(eng, opp, 1, 3, 402)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	assert_array(eng.state.players[opp].board).not_contains([def])
	assert_array(eng.state.players[opp].discard).contains([def])
	assert_int(atk.current_health).is_equal(3)

func test_unit_vs_unit_simultaneous_trade() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var atk := _place(eng, me, 3, 3, 403)
	var def := _place(eng, opp, 3, 3, 404)
	eng.apply(Action.declare_attack(atk.instance_id, {"unit": def.instance_id}))
	assert_array(eng.state.players[me].board).not_contains([atk])
	assert_array(eng.state.players[opp].board).not_contains([def])

func test_deck_attack_has_no_retaliation() -> void:
	var eng := _engine()
	var atk := _place(eng, eng.state.active_player, 1, 1, 405)
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_int(atk.current_health).is_equal(1)
