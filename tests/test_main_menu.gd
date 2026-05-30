extends GdUnitTestSuite

func _spawn() -> MainMenu:
	var m: MainMenu = load("res://src/ui/menu/main_menu.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_deck_path_for_color() -> void:
	assert_str(MainMenu.deck_path("strike")).is_equal("res://src/data/decks/strike.csv")
	assert_str(MainMenu.deck_path("audio")).is_equal("res://src/data/decks/audio.csv")

func test_selecting_a_deck_sets_choice() -> void:
	var m := _spawn()
	m.select_deck("raccoon")
	assert_str(m.chosen_deck).is_equal("raccoon")