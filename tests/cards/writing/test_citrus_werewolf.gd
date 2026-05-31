# tests/cards/writing/test_citrus_werewolf.gd
extends WritingTestBase

func test_gains_orange_on_dealing_deck_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var wolf := place_on_board(eng, me, writing_def(4))
	wolf.tapped = false
	var before := oranges_in_hand(eng, me)
	eng.apply(Action.declare_attack(wolf.instance_id, {"deck": true}))
	assert_int(oranges_in_hand(eng, me)).is_equal(before + 1)
