extends CardTestBase

func test_opponent_mills_two_on_attack_when_choosing_option_one() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var red := place_on_board(eng, me, strike_def(7))
	red.tapped = false
	var opp_deck_before := eng.state.players[opp].deck.size()
	eng.apply(Action.declare_attack(red.instance_id, {"deck": true}))
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("choose_option")
	assert_int(eng.state.pending_choice.player).is_equal(opp)
	eng.apply(Action.resolve_choice({"option": 1}))
	assert_int(eng.state.players[opp].discard.size()).is_greater_equal(2)
