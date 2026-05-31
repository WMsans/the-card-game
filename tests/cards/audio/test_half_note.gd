extends AudioTestBase

func test_half_note_gains_damage_and_health_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(4))
	var bd := note.current_damage
	var bh := note.current_health
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_damage).is_equal(bd + 1)
	assert_int(note.current_health).is_equal(bh + 2)
