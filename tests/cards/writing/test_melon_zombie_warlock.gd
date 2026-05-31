# tests/cards/writing/test_melon_zombie_warlock.gd
extends WritingTestBase

func test_replay_keeps_minion_and_charges_cost_plus_one() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	ps.tickets_tapped = 0
	place_on_board(eng, me, writing_def(9))  # Warlock provides the replacement
	var minion := place_on_board(eng, me, TestFactory.minion(3, 2, 2, 1))
	EffectContext.new(eng, me).trash(minion)
	# menu: option 0 = "Replay for cost +1", last = "Just KO it"
	assert_str(eng.state.pending_choice.kind).is_equal("trash_choice")
	eng.apply(Action.resolve_choice({"option": 0}))
	assert_bool(ps.board.has(minion)).is_true()      # stayed on board
	assert_int(ps.tickets_tapped).is_equal(4)         # 3 + 1
