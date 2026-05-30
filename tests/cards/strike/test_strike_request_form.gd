extends CardTestBase

func test_draws_first_request_card_from_deck() -> void:
	var eng := fresh_engine()
	eng.state.active_player = 0
	var red := eng.state.make_instance(strike_def(7))
	red.card_script = HasReq.new()
	red.zone = Enums.Zone.DECK
	eng.state.players[0].deck.append(red)
	var form := put_in_hand(eng, 0, strike_def(2))
	eng.apply(Action.play_card(form.instance_id))
	assert_bool(eng.state.players[0].hand.has(red)).is_true()
