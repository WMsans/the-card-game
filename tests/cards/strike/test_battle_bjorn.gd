extends CardTestBase

func test_sets_global_request_flag_on_cast() -> void:
	var eng := fresh_engine()
	var bjorn := put_in_hand(eng, 0, strike_def(1))
	eng.apply(Action.play_card(bjorn.instance_id))
	assert_bool(eng.state.players[0].all_requests_met_this_turn).is_true()
