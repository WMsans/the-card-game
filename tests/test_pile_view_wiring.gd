extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func test_clicking_player_deck_opens_overlay() -> void:
	var m := await _match()
	m._on_pile_clicked(Enums.Zone.DECK, 0)
	assert_bool(m._pile_overlay.is_open()).is_true()

func test_opp_deck_click_opens_overlay_when_not_attacking() -> void:
	var m := await _match()
	m.handle_deck_target_clicked()
	assert_bool(m._pile_overlay.is_open()).is_true()

func test_opp_deck_click_attacks_when_attacker_selected() -> void:
	var m := await _match()
	m._selected_attacker = 999   # pretend an attacker is mid-selection
	m.handle_deck_target_clicked()
	assert_bool(m._pile_overlay.is_open()).is_false()
