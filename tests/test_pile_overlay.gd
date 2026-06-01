extends GdUnitTestSuite

const OVERLAY := "res://src/ui/table/pile_overlay.tscn"

func _inst(id: int, type: int, name: String) -> CardInstance:
	var d := CardDefinition.new()
	d.type = type
	d.name = name
	return CardInstance.new(id, d)

func _overlay() -> PileOverlay:
	var o: PileOverlay = load(OVERLAY).instantiate()
	add_child(o)
	auto_free(o)
	return o

func _three_cards() -> Array[CardInstance]:
	var cards: Array[CardInstance] = [
		_inst(1, Enums.CardType.SPELL, "Zap"),
		_inst(2, Enums.CardType.MINION, "Badger"),
		_inst(3, Enums.CardType.MINION, "Ant"),
	]
	return cards

func test_open_spawns_one_card_per_instance_in_sorted_order() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Your Deck")
	await get_tree().process_frame
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	assert_int(grid.get_child_count()).is_equal(3)
	# Sorted: Minion(Ant, Badger), Spell(Zap)
	assert_str(grid.get_child(0)._instance.definition.name).is_equal("Ant")
	assert_str(grid.get_child(1)._instance.definition.name).is_equal("Badger")
	assert_str(grid.get_child(2)._instance.definition.name).is_equal("Zap")

func test_open_sets_title_and_visible() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Opponent's Discard")
	assert_bool(o.visible).is_true()
	assert_bool(o.is_open()).is_true()
	var title: Label = o.find_child("Title") as Label
	assert_str(title.text).is_equal("Opponent's Discard")

func test_empty_pile_does_not_open() -> void:
	var o := _overlay()
	var empty: Array[CardInstance] = []
	o.open(empty, Vector2(1700, 800), "Your Discard")
	assert_bool(o.is_open()).is_false()
	assert_bool(o.visible).is_false()

func test_second_open_is_ignored_while_open() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Your Deck")
	await get_tree().process_frame
	var more: Array[CardInstance] = [_inst(9, Enums.CardType.TRAP, "Extra")]
	o.open(more, Vector2(0, 0), "Other")
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	assert_int(grid.get_child_count()).is_equal(3)

func test_close_frees_cards_and_hides() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Your Deck")
	await get_tree().process_frame
	o.close()
	await get_tree().create_timer(0.25).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	assert_int(grid.get_child_count()).is_equal(0)
	assert_bool(o.visible).is_false()
	assert_bool(o.is_open()).is_false()

func test_cards_land_at_their_grid_slots() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Your Deck")
	await get_tree().create_timer(1.2).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	for cv in grid.get_children():
		assert_bool(cv._rest_set).is_true()
		assert_vector(cv.position).is_equal_approx(cv._rest_position, Vector2(2, 2))

func test_face_down_open_keeps_cards_face_down() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 400), "Opponent's Traps", true)
	# Wait past the normal flip window.
	await get_tree().create_timer(1.2).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	for cv in grid.get_children():
		assert_bool(cv._face_down).is_true()

func test_default_open_flips_cards_face_up() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 400), "Your Traps")
	await get_tree().create_timer(1.2).timeout
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	var any_face_up := false
	for cv in grid.get_children():
		if not cv._face_down:
			any_face_up = true
	assert_bool(any_face_up).is_true()

func test_cards_start_offset_from_their_slot() -> void:
	var o := _overlay()
	o.open(_three_cards(), Vector2(1700, 800), "Your Deck")
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: GridContainer = o.find_child("Grid") as GridContainer
	var moved := false
	for cv in grid.get_children():
		if cv.position.distance_to(cv._rest_position) > 5.0:
			moved = true
	assert_bool(moved).is_true()
