extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_match_has_director() -> void:
	var m := _spawn()
	assert_object(m._director).is_not_null()

func test_end_turn_is_ignored_while_animating() -> void:
	var m := _spawn()
	# Human's turn; an end-turn would normally append events to the bus log.
	m._anim_busy = true
	var before: int = m.state.bus.log.size()
	m._on_end_turn_pressed()
	assert_int(m.state.bus.log.size()).is_equal(before)

func test_unit_click_is_ignored_while_animating() -> void:
	var m := _spawn()
	m._anim_busy = true
	# Should early-return without selecting an attacker or erroring.
	m.handle_unit_clicked(999)
	assert_int(m._selected_attacker).is_equal(-1)
