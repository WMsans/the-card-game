# tests/test_landing_panel.gd
extends GdUnitTestSuite

func _spawn() -> LandingPanel:
	var p: LandingPanel = load("res://src/ui/shell/landing_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_play_button_emits_play_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.play_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Play").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_each_menu_button_emits_its_intent() -> void:
	var p := _spawn()
	var seen := {}
	p.compendium_pressed.connect(func() -> void: seen["c"] = true)
	p.settings_pressed.connect(func() -> void: seen["s"] = true)
	p.quit_pressed.connect(func() -> void: seen["q"] = true)
	p.credits_pressed.connect(func() -> void: seen["cr"] = true)
	p.get_node("%Compendium").pressed.emit()
	p.get_node("%Settings").pressed.emit()
	p.get_node("%Quit").pressed.emit()
	p.get_node("%Credits").pressed.emit()
	assert_bool(seen.has("c") and seen.has("s") and seen.has("q") and seen.has("cr")).is_true()

func test_creates_drifting_card_sprites() -> void:
	var p := _spawn()
	var cards: Node = p.get_node("DriftingCards")
	assert_int(cards.get_child_count()).is_equal(p.DRIFT_COUNT)

func test_foreground_offset_moves_drifting_cards_container() -> void:
	var p := _spawn()
	p.on_foreground_offset(Vector2(11, 13))
	assert_vector(p.get_node("DriftingCards").position).is_equal(Vector2(11, 13))
