extends GdUnitTestSuite

func _engine_in_main(seed_value: int) -> GameEngine:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		en.apply(AiController.choice_action(en))
	return en

func test_choose_action_returns_a_legal_action() -> void:
	var en := _engine_in_main(11)
	var act := AiController.choose_action(en)
	assert_object(act).is_not_null()
	var legal := en.get_legal_actions()
	var found := legal.filter(func(a): return a.type == act.type and a.params == act.params)
	assert_int(found.size()).is_greater(0)

func test_turn_terminates_within_bounded_steps() -> void:
	var en := _engine_in_main(11)
	var start_player := en.state.active_player
	var steps := 0
	while en.state.active_player == start_player and en.state.pending_choice == null \
			and en.state.phase != Enums.Phase.GAME_OVER and steps < 50:
		en.apply(AiController.choose_action(en))
		steps += 1
	assert_bool(en.state.active_player != start_player or en.state.phase == Enums.Phase.GAME_OVER).is_true()

func test_mulligan_choice_discards_exactly_two() -> void:
	var st := GameState.new(5)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	var act := AiController.choice_action(en)
	assert_int(act.type).is_equal(Enums.ActionType.MULLIGAN)
	assert_int(act.params["indices"].size()).is_equal(2)

func test_ai_resolves_select_cards_with_minimum() -> void:
	var state := GameState.new(4)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var spec := ChoiceSpec.select_cards([], 0, 3, "x")
	state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	var a := AiController.choice_action(eng)
	assert_int(a.type).is_equal(Enums.ActionType.RESOLVE_CHOICE)
	assert_array(a.params["indices"]).is_equal([])     # min 0 -> pick none

func test_ai_resolves_choose_option_picks_first() -> void:
	var state := GameState.new(4)
	var eng := GameEngine.new(state)
	var spec := ChoiceSpec.choose_option(["A", "B"], "x")
	state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "choose_option"})
	var a := AiController.choice_action(eng)
	assert_int(a.params["option"]).is_equal(0)