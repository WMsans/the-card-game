# tests/cards/writing/test_melon_zombie.gd
extends WritingTestBase

func test_may_return_to_hand_when_trashed() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var z := place_on_board(eng, me, writing_def(11))
	EffectContext.new(eng, me).trash(z)
	# replacement menu: option 0 = "Return to hand", last = "Just KO it"
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(eng.state.players[me].hand.has(z)).is_true()
	assert_bool(eng.state.players[me].discard.has(z)).is_false()
