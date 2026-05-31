extends RaccoonTestBase

func test_rummages_two_then_puts_two_hand_cards_to_deck_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.hand.clear()
	seed_discard(eng, me, 3)
	var h1 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 10))
	var h2 := eng.state.make_instance(TestFactory.minion(1, 1, 1, 11))
	h1.zone = Enums.Zone.HAND; h2.zone = Enums.Zone.HAND
	ps.hand.append(h1); ps.hand.append(h2)
	var spell := eng.state.make_instance(raccoon_def(14))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	# rummaged 2 into hand; now asked to pick 2 to send to deck bottom
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	var i1 := ps.hand.find(h1)
	var i2 := ps.hand.find(h2)
	eng.apply(Action.resolve_choice({"indices": [i1, i2]}))
	assert_bool(ps.deck.has(h1) and ps.deck.has(h2)).is_true()
	assert_bool(ps.hand.has(h1) or ps.hand.has(h2)).is_false()
