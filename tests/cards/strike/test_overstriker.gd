extends CardTestBase

func test_mills_opponent_when_they_play_expensive_card() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	place_on_board(eng, me, strike_def(13))
	# Discard excess cards from hand to avoid over-limit end_turn stall
	var ps_me := eng.state.players[me]
	while ps_me.hand.size() > 5:
		var c: CardInstance = ps_me.hand.back()
		if c.definition.type == Enums.CardType.LEADER:
			break
		ps_me.hand.erase(c)
		c.zone = Enums.Zone.DISCARD
		ps_me.discard.append(c)
	eng.apply(Action.end_turn())
	var ps := eng.state.active()
	var pricey := eng.state.make_instance(TestFactory.minion(8, 5, 5, 900))
	pricey.zone = Enums.Zone.HAND
	ps.hand.append(pricey)
	ps.tickets_total = 20
	var deck_before := ps.deck.size()
	eng.apply(Action.play_card(pricey.instance_id))
	assert_int(ps.deck.size()).is_equal(deck_before - 1)
