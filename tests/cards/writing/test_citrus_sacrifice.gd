# tests/cards/writing/test_citrus_sacrifice.gd
extends WritingTestBase

func test_gains_one_orange_per_discard_card_capped_at_five() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	for i in range(7):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 600 + i))
		c.zone = Enums.Zone.DISCARD
		ps.discard.append(c)
	var spell := eng.state.make_instance(writing_def(15))
	ps.hand.append(spell)
	ps.tickets_total = 20
	eng.apply(Action.play_card(spell.instance_id))
	assert_int(oranges_in_hand(eng, me)).is_equal(5)  # capped
