extends AudioTestBase

func test_eighth_note_gains_three_damage_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(6))
	var bd := note.current_damage
	EffectContext.new(eng, me).harmonize()
	assert_int(note.current_damage).is_equal(bd + 3)
