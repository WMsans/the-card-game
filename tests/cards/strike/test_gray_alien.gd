extends CardTestBase

func test_discards_chosen_then_draws_count_plus_one() -> void:
	var eng := fresh_engine()
	var ps := eng.state.players[0]
	var extra := put_in_hand(eng, 0, strike_def(2))
	var gray := put_in_hand(eng, 0, strike_def(9))
	var deck_before := ps.deck.size()
	eng.apply(Action.play_card(gray.instance_id))
	assert_str(eng.state.pending_choice.kind).is_equal("card_effect")
	var spec: ChoiceSpec = eng.state.pending_choice.data["spec"]
	var idx := spec.cards.find(extra)
	eng.apply(Action.resolve_choice({"indices": [idx]}))
	assert_bool(ps.discard.has(extra)).is_true()
	assert_int(ps.deck.size()).is_equal(deck_before - 2)
