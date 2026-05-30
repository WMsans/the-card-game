extends CardTestBase

func test_kills_chosen_low_health_unit_on_second_attack() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ghost := place_on_board(eng, me, strike_def(8))
	var a1 := place_on_board(eng, me, strike_def(2)); a1.tapped = false
	var a2 := place_on_board(eng, me, strike_def(3)); a2.tapped = false
	var victim := place_on_board(eng, 1 - me, strike_def(2))
	eng.apply(Action.declare_attack(a1.instance_id, {"deck": true}))
	eng.apply(Action.declare_attack(a2.instance_id, {"deck": true}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [victim.instance_id]}))
	assert_bool(eng.state.players[1 - me].board.has(victim)).is_false()
