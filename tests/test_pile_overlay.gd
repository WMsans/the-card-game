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
