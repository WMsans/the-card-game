extends AudioTestBase

func test_quarter_note_gains_two_damage_once_on_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(2))
	var base := note.current_damage
	var ctx := EffectContext.new(eng, me)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(base + 2)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(base + 2)  # only once

func test_quarter_note_is_a_note() -> void:
	assert_bool(CardScriptRegistry.get_script_for("audio", 2).is_note()).is_true()
