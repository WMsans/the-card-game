extends AudioTestBase

func test_whole_note_gains_health_and_taunt_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(10))
	var bh := note.current_health
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_health).is_equal(bh + 2)
	assert_bool(note.vars.get("taunt", false)).is_true()
