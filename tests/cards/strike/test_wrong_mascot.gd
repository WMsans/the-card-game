extends CardTestBase

func test_kills_attacker_of_met_request_minion() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var trapper := eng.state.opponent()
	var defender := place_on_board(eng, trapper, strike_def(11))
	eng.state.players[trapper].all_requests_met_this_turn = true
	var trap := eng.state.make_instance(strike_def(19))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[trapper].set_traps.append(trap)
	var attacker := place_on_board(eng, me, strike_def(2))
	attacker.tapped = false
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": defender.instance_id}))
	assert_bool(eng.state.players[me].board.has(attacker)).is_false()
	assert_bool(eng.state.players[trapper].discard.has(trap)).is_true()
