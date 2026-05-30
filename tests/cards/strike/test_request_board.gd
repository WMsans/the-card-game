extends CardTestBase

func test_summons_only_minions_whose_request_is_met() -> void:
	var eng := fresh_engine()
	eng.state.players[0].all_requests_met_this_turn = true
	var slacker := put_in_hand(eng, 0, strike_def(11))
	var board := put_in_hand(eng, 0, strike_def(15))
	eng.apply(Action.play_card(board.instance_id))
	assert_bool(eng.state.players[0].board.has(slacker)).is_true()
