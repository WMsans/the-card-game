extends GdUnitTestSuite

func _spawn() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_human_mulligan_shows_panel_ai_resolves_automatically() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	assert_bool(m.get_node("MulliganPanel").visible).is_true()
	m.get_node("MulliganPanel").confirmed.emit([0, 1])
	await get_tree().create_timer(0.6).timeout
	assert_bool(m.state.pending_choice == null).is_true()

func test_game_over_panel_shows_on_game_over() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	m.state.phase = Enums.Phase.GAME_OVER
	m.state.winner = 0
	m._show_game_over()
	assert_bool(m.get_node("GameOverPanel").visible).is_true()

func test_select_cards_choice_shows_card_select_panel() -> void:
	var m: Node = _spawn()
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	var spec := ChoiceSpec.select_cards(m.state.players[0].hand, 0, 1, "Pick")
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("CardSelectPanel").visible).is_true()