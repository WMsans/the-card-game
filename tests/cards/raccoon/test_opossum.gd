extends RaccoonTestBase

func test_opossum_rummages_three_on_cast() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	seed_discard(eng, me, 4)
	ps.tickets_total = 20
	var op := eng.state.make_instance(raccoon_def(4))
	op.zone = Enums.Zone.HAND
	ps.hand.append(op)
	var hand_before := ps.hand.size()
	eng.apply(Action.play_card(op.instance_id))
	# 3 cards rummaged into hand; opossum itself left hand to the board
	assert_int(ps.hand.size()).is_equal(hand_before - 1 + 3)
	assert_int(ps.discard.size()).is_equal(1)
