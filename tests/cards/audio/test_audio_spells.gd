extends AudioTestBase

func _cast(eng: GameEngine, me: int, id: int) -> CardInstance:
	var ps := eng.state.players[me]
	var c := eng.state.make_instance(audio_def(id))
	c.zone = Enums.Zone.HAND
	ps.hand.append(c)
	ps.tickets_total = 20
	eng.apply(Action.play_card(c.instance_id))
	return c

func test_harmonize_spell_triggers_harmonize() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, audio_def(2))
	var bd := note.current_damage
	_cast(eng, me, 14)
	assert_int(note.current_damage).is_equal(bd + 2)

func test_staccato_sets_notes_double_damage_flag() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_cast(eng, me, 16)
	assert_bool(eng.state.turn_flags.get("notes_double_damage", false)).is_true()

func test_legato_untaps_a_chosen_unit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var tapped := place_on_board(eng, me, TestFactory.minion(1, 1, 1, 1))
	tapped.tapped = true
	_cast(eng, me, 18)
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_target")
	eng.apply(Action.resolve_choice({"target_ids": [tapped.instance_id]}))
	assert_bool(tapped.tapped).is_false()
