extends CardTestBase

func test_moves_request_card_from_discard_to_deck_and_taps() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var raise := place_on_board(eng, me, strike_def(4))
	raise.tapped = false
	var req := eng.state.make_instance(strike_def(11))
	req.zone = Enums.Zone.DISCARD
	eng.state.players[me].discard.append(req)
	eng.apply(Action.activate_ability(raise.instance_id, "raise"))
	var spec: ChoiceSpec = eng.state.pending_choice.data["spec"]
	eng.apply(Action.resolve_choice({"indices": [spec.cards.find(req)]}))
	assert_bool(eng.state.players[me].deck.has(req)).is_true()
	assert_bool(eng.state.players[me].discard.has(req)).is_false()
	assert_bool(raise.tapped).is_true()
