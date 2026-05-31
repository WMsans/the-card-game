extends AudioTestBase

class DoublerStub extends CardScript:
	func doubles_all_damage() -> bool: return true

func test_bass_clef_style_doubles_effect_damage() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var clef := place_on_board(eng, me, TestFactory.minion(5, 0, 5, 13))
	clef.card_script = DoublerStub.new()
	var victim := place_on_board(eng, me, TestFactory.minion(1, 1, 10, 1))
	eng._damage_unit(victim, 3)
	assert_int(victim.current_health).is_equal(4)

class NoteStub extends CardScript:
	func is_note() -> bool: return true

func test_staccato_flag_doubles_note_damage_only() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, TestFactory.minion(2, 1, 10, 2))
	note.card_script = NoteStub.new()
	var plain := place_on_board(eng, me, TestFactory.minion(2, 1, 10, 3))
	eng.state.turn_flags["notes_double_damage"] = true
	eng._damage_unit(note, 2)
	eng._damage_unit(plain, 2)
	assert_int(note.current_health).is_equal(6)
	assert_int(plain.current_health).is_equal(8)
