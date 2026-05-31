extends CardTestBase

func test_kills_non_request_units_and_ends_turn() -> void:
	var eng := fresh_engine()
	var attacker_turn := eng.state.active_player
	var vanilla := place_on_board(eng, attacker_turn, strike_def(2))
	var req := place_on_board(eng, attacker_turn, strike_def(11))
	eng.state.players[attacker_turn].all_requests_met_this_turn = true
	var ps := eng.state.players[attacker_turn]
	for _i in range(2):
		var c := ps.hand[0]
		ps.hand.erase(c)
		c.zone = Enums.Zone.DISCARD
		ps.discard.append(c)
	var hammer := put_in_hand(eng, attacker_turn, strike_def(17))
	eng.apply(Action.play_card(hammer.instance_id))
	assert_bool(eng.state.players[attacker_turn].board.has(vanilla)).is_false()
	assert_int(eng.state.active_player).is_not_equal(attacker_turn)
