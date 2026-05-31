extends CardTestBase

func test_puts_chosen_enemy_minion_on_deck_top() -> void:
	var eng := fresh_engine()
	var enemy := place_on_board(eng, 1, strike_def(2))
	var slacker := put_in_hand(eng, 0, strike_def(11))
	eng.apply(Action.play_card(slacker.instance_id))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [enemy.instance_id]}))
	assert_object(eng.state.players[1].deck[0]).is_equal(enemy)
	assert_bool(eng.state.players[1].board.has(enemy)).is_false()
