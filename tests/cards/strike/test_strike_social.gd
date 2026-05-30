extends CardTestBase

func test_met_request_minions_survive_combat_after_trap() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var trapper := eng.state.opponent()
	var protege := place_on_board(eng, trapper, strike_def(11))
	eng.state.players[trapper].all_requests_met_this_turn = true
	var trap := eng.state.make_instance(strike_def(21))
	trap.zone = Enums.Zone.TRAP_SET
	eng.state.players[trapper].set_traps.append(trap)
	var attacker := place_on_board(eng, me, strike_def(8))
	attacker.tapped = false
	eng.apply(Action.declare_attack(attacker.instance_id, {"unit": protege.instance_id}))
	assert_bool(eng.state.players[trapper].board.has(protege)).is_true()
