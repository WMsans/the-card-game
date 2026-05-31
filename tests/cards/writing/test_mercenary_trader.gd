# tests/cards/writing/test_mercenary_trader.gd
extends WritingTestBase

func test_gains_orange_when_trashed() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var merc := place_on_board(eng, me, writing_def(13))
	var before := oranges_in_hand(eng, me)
	EffectContext.new(eng, me).trash(merc)
	assert_int(oranges_in_hand(eng, me)).is_equal(before + 1)
