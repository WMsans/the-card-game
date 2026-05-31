extends AudioTestBase

func test_clef_bounce_returns_to_hand_for_two_tickets() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 5
	ps.tickets_tapped = 0
	var clef := place_on_board(eng, me, audio_def(12))
	eng.apply(Action.activate_ability(clef.instance_id, "clef_bounce"))
	assert_bool(ps.hand.has(clef)).is_true()
	assert_bool(ps.board.has(clef)).is_false()
	assert_int(ps.tickets_tapped).is_equal(2)

func test_treble_clef_harmonizes_every_second_turn() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	place_on_board(eng, me, audio_def(12))
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	assert_int(note.current_damage).is_equal(bd)
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": me}))
	assert_int(note.current_damage).is_equal(bd + 2)

func test_bass_clef_harmonizes_when_a_unit_survives_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	place_on_board(eng, me, audio_def(13))
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	var survivor := place_on_board(eng, me, TestFactory.minion(1, 1, 20, 1))
	eng._damage_unit(survivor, 2)
	assert_int(note.current_damage).is_equal(bd + 2)
