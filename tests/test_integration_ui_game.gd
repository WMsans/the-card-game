extends GdUnitTestSuite

func test_ai_vs_ai_reaches_game_over() -> void:
	var st := GameState.new(2024)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	var steps := 0
	while st.phase != Enums.Phase.GAME_OVER and steps < 5000:
		if st.pending_choice != null:
			en.apply(AiController.choice_action(en))
		else:
			en.apply(AiController.choose_action(en))
		steps += 1
	assert_int(st.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_int(st.winner).is_between(0, 1)