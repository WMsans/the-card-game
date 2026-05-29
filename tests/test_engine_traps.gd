extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(8)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_set_vanilla_trap_does_not_fire_on_opponent_attack() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var trap := eng.state.make_instance(TestFactory.trap(2, 500))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[opp].set_traps.append(trap)
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 501))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	eng.state.players[me].board.append(atk)
	eng.apply(Action.declare_attack(atk.instance_id, {"deck": true}))
	assert_array(eng.state.players[opp].set_traps).contains([trap])
	assert_object(eng.state.pending_choice).is_null()

func test_trap_condition_is_inert() -> void:
	var eng := _engine()
	var trap := eng.state.make_instance(TestFactory.trap(2, 502))
	assert_bool(eng._trap_condition_met(trap, GameEvent.new(Enums.EventType.UNIT_ATTACKED))).is_false()
