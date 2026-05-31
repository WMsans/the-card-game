extends WritingTestBase

func test_shelley_can_send_trashed_unit_to_deck_bottom() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	var shelley := place_on_board(eng, me, writing_def(1))
	var victim := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	EffectContext.new(eng, me).trash(victim)
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(ps.deck.has(victim)).is_true()
	assert_bool(ps.discard.has(victim)).is_false()
