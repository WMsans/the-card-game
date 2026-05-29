extends GdUnitTestSuite

func _play_to_end(eng: GameEngine, max_steps: int) -> void:
	var steps := 0
	while eng.state.phase != Enums.Phase.GAME_OVER and steps < max_steps:
		steps += 1
		var actions := eng.get_legal_actions()
		var chosen: Action = null
		for a in actions:
			if a.type == Enums.ActionType.DECLARE_ATTACK and a.params["target"].get("deck", false):
				chosen = a
				break
		if chosen == null:
			for a in actions:
				if a.type == Enums.ActionType.PLAY_CARD:
					chosen = a
					break
		if chosen == null:
			chosen = Action.end_turn()
		eng.apply(chosen)

func _new_started(seed_value: int) -> GameEngine:
	var state := GameState.new(seed_value)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_full_vanilla_game_reaches_a_winner() -> void:
	var eng := _new_started(1234)
	_play_to_end(eng, 2000)
	assert_int(eng.state.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_bool(eng.state.winner == 0 or eng.state.winner == 1).is_true()

func test_same_seed_same_script_is_deterministic() -> void:
	var a := _new_started(777)
	var b := _new_started(777)
	_play_to_end(a, 2000)
	_play_to_end(b, 2000)
	assert_int(a.state.winner).is_equal(b.state.winner)
	assert_int(a.state.turn_number).is_equal(b.state.turn_number)
	assert_int(a.state.bus.log.size()).is_equal(b.state.bus.log.size())
